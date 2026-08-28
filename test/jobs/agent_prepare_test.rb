require "test_helper"

# D-agent-prepared-work: "Active" means the agent arrives with the work
# already done — and still lands none of it until the click. The whole
# feature turns on one guarantee, which is what most of these tests are
# about: a prepared run leaves nothing in the user's data until Save.
class AgentPrepareTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    # find_care is a draft tool whose one required input the checkup
    # watcher already prefills — the real preparable path, not a fixture.
    @suggestion = @user.suggestions.create!(
      watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence/dental/2026h2",
      title: "Book a dental cleaning",
      action: { "tool" => { "slug" => "find_care", "inputs" => { "specialty" => "dentist" } } }
    )
    @suggestion.sections = [ sections(:health) ]
  end

  test "a prepared run holds the draft and creates nothing" do
    stub_llm(draft: { title: "How to find a dentist", body: "Call your insurer's member line…" },
      follow_ups: [ { title: "Call member services", due_on: 3.days.from_now.to_date.iso8601 } ])

    assert_no_difference [ -> { @user.notes.count }, -> { @user.tasks.count }, -> { @user.events.count } ] do
      AgentPrepareJob.perform_now(@suggestion)
    end

    run = @suggestion.reload.tool_run
    assert_predicate run, :prepared?
    assert_predicate run, :origin_agent?
    assert_empty run.items, "nothing is recorded on the run either — the intents are not rows"

    draft, follow_up = run.landings
    assert_equal "note", draft.kind
    assert_equal "How to find a dentist", draft.title
    assert_equal "task", follow_up.kind
    assert_equal "Call member services", follow_up.title
  end

  test "the suggestion advertises the draft and stays pending" do
    stub_llm(draft: { title: "How to find a dentist", body: "…" }, follow_ups: [])

    AgentPrepareJob.perform_now(@suggestion)

    assert_predicate @suggestion.reload, :prepared?
    assert_predicate @suggestion, :pending?, "preparing is not accepting"
    assert_equal "Review draft", @suggestion.accept_label
  end

  test "saving lands the intents as ordinary primitives, filed where the tool files" do
    stub_llm(draft: { title: "How to find a dentist", body: "Call your insurer…" },
      follow_ups: [ { title: "Call member services", due_on: 3.days.from_now.to_date.iso8601 } ])
    AgentPrepareJob.perform_now(@suggestion)
    run = @suggestion.reload.tool_run

    created = nil
    assert_difference [ -> { @user.notes.count }, -> { @user.tasks.count } ], 1 do
      created = run.land!
    end

    assert_predicate run.reload, :done?
    note = created.grep(Note).sole
    assert_equal "How to find a dentist", note.title
    assert_includes note.sections, sections(:health), "the tool's own filing came through the intent"
    assert_equal created.sort_by(&:id), run.items.sort_by(&:id), "landed items are recorded on the run"
  end

  test "a task whose prepared date has since passed lands in Today" do
    # The schedule_task rule: dates are resolved at the click, not at
    # preparation — a draft prepared Monday and saved Thursday means Thursday.
    stub_llm(draft: { title: "Plan", body: "…" },
      follow_ups: [ { title: "Call them", due_on: Date.current.iso8601 } ])
    AgentPrepareJob.perform_now(@suggestion)

    task = @suggestion.reload.tool_run.land!.grep(Task).sole
    assert_predicate task, :today?
  end

  test "discarding leaves no trace" do
    stub_llm(draft: { title: "Draft", body: "…" }, follow_ups: [ { title: "A task", due_on: nil } ])
    AgentPrepareJob.perform_now(@suggestion)
    run = @suggestion.reload.tool_run

    assert_no_difference [ -> { @user.notes.count }, -> { @user.tasks.count } ] do
      run.discard!
    end

    assert_predicate run.reload, :discarded?
    assert_not @suggestion.reload.prepared?, "a discarded run stops advertising a draft"
  end

  test "a failed preparation degrades to the plain prefilled redirect" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "down")

    assert_nothing_raised { AgentPrepareJob.perform_now(@suggestion) }

    assert_nil @suggestion.reload.tool_run, "the suggestion is exactly what it was before"
    assert_predicate @suggestion, :pending?
    assert_equal "Open tool", @suggestion.accept_label
    assert_equal 0, ToolRun.count, "no failed run nobody asked for is left lying around"
    assert AppError.exists?(source: "AgentPrepareJob"), "silent for the user, not for /admin"
  end

  test "a model that returns nothing usable prepares nothing" do
    stub_request(:post, ENDPOINT).to_return(status: 200,
      body: { choices: [ { message: { content: { draft: { title: "x", body: "" } }.to_json } } ] }.to_json)

    AgentPrepareJob.perform_now(@suggestion)

    assert_nil @suggestion.reload.tool_run
    assert_equal 0, ToolRun.count
  end

  test "preparation never runs twice for one suggestion" do
    stub_llm(draft: { title: "Draft", body: "…" }, follow_ups: [])
    AgentPrepareJob.perform_now(@suggestion)
    first = @suggestion.reload.tool_run

    AgentPrepareJob.perform_now(@suggestion)

    assert_equal first, @suggestion.reload.tool_run
    assert_equal 1, ToolRun.count
  end

  test "a draft never outlives the nudge that occasioned it" do
    # A prepared letter about a bill since paid is worse than a stale
    # nudge: it looks like work waiting to be done.
    stub_llm(draft: { title: "Draft", body: "…" }, follow_ups: [])
    AgentPrepareJob.perform_now(@suggestion)
    run = @suggestion.reload.tool_run

    @suggestion.resolve!

    assert_predicate run.reload, :discarded?
    assert_not @suggestion.reload.prepared?
  end

  test "a suggestion settled between the scan and the job is not drafted for" do
    stub_llm(draft: { title: "Draft", body: "…" }, follow_ups: [])
    @suggestion.dismiss!

    AgentPrepareJob.perform_now(@suggestion)

    assert_equal 0, ToolRun.count, "no tokens spent on work nobody will be shown"
  end

  # ── What is preparable ────────────────────────────────────────────────

  test "a suggestion whose tool still needs an answer is not preparable" do
    @suggestion.update!(action: { "tool" => { "slug" => "find_care", "inputs" => {} } })

    assert_nil @suggestion.preparable_tool, "the form would still have a question to ask"
  end

  test "plan and chat tools are never preparable" do
    @suggestion.update!(action: { "tool" => { "slug" => "learn_something",
                                              "inputs" => { "topic" => "Portuguese" } } })
    assert_nil @suggestion.preparable_tool, "a prepared Goal is a deferred graph, not a draft"

    @suggestion.update!(action: { "tool" => { "slug" => "tutor", "inputs" => { "topic" => "algebra" } } })
    assert_nil @suggestion.preparable_tool, "a conversation cannot be had in advance"
  end

  test "a plain task payload is not preparable" do
    @suggestion.update!(action: { "task" => { "title" => "Book a checkup" } })

    assert_nil @suggestion.preparable_tool
  end

  private
    def stub_llm(draft:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { draft: draft, follow_ups: follow_ups }.to_json } } ] }.to_json
      )
    end
end
