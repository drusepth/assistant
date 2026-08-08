require "test_helper"

# The first letter tool where the document is optional — one line of facts
# plus placeholders is enough to put a formal demand in the user's hands.
class DepositDemandToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "drafts the demand from details alone, with no document" do
    run = users(:one).tool_runs.create!(
      tool_slug: "deposit_demand",
      inputs: { "details" => "Moved out June 30, $1,800 deposit, 12 Oak St" }
    )
    stub_llm(
      letter: { title: nil, body: "This letter is a formal demand for the return of my $1,800 security deposit..." },
      follow_ups: [ { title: "Send by certified mail", due_on: nil } ],
      deadlines: [ { title: "Response deadline set in the letter", date: 14.days.from_now.to_date.iso8601 } ]
    )

    ToolRunJob.perform_now(run)

    run.reload
    assert run.done?

    letter = run.items.grep(Note).sole
    assert_equal "Deposit demand letter", letter.title, "no document — the prefix stands alone"
    assert_equal [ sections(:renting), sections(:disputes) ].sort_by(&:id), letter.sections.sort_by(&:id)

    assert_equal 1, run.items.grep(Event).count
    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("12 Oak St") && !request.body.include?("The document (titled")
    end
  end

  test "the household's own address rides along as the letterhead (D-household-profile)" do
    users(:one).household.update!(address: "123 Maple Street\nAustin, TX 78701", phone: "(512) 555-0142")
    run = users(:one).tool_runs.create!(tool_slug: "deposit_demand", inputs: { "details" => "Moved out June 30" })
    stub_llm(letter: { title: nil, body: "..." }, follow_ups: [], deadlines: [])

    ToolRunJob.perform_now(run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("123 Maple Street") && request.body.include?("(512) 555-0142")
    end
  end

  test "a household that never filled in an address sends no letterhead block" do
    run = users(:one).tool_runs.create!(tool_slug: "deposit_demand", inputs: { "details" => "Moved out June 30" })
    stub_llm(letter: { title: nil, body: "..." }, follow_ups: [], deadlines: [])

    ToolRunJob.perform_now(run)

    assert_requested(:post, ENDPOINT) { |request| !request.body.include?("letterhead") }
  end

  test "a chosen lease joins the prompt and the filing" do
    lease = users(:one).documents.create!(title: "Oak St lease", extracted_text: "Security deposit: $1,800...")
    lease.sections << sections(:money)
    run = users(:one).tool_runs.create!(
      tool_slug: "deposit_demand",
      inputs: { "details" => "moved out June 30", "document_id" => lease.id.to_s }
    )
    stub_llm(letter: { title: "Demand", body: "..." }, follow_ups: [], deadlines: [])

    ToolRunJob.perform_now(run)

    letter = run.reload.items.grep(Note).sole
    assert_includes letter.sections, sections(:money), "the lease's own filing is inherited"
    assert_requested(:post, ENDPOINT) { |request| request.body.include?("Oak St lease") }
  end

  test "the details input is required to start a run" do
    run = users(:one).tool_runs.new(tool_slug: "deposit_demand", inputs: {})

    assert_not run.valid?
    assert_match(/The basics/, run.errors.full_messages.to_sentence)
  end

  private
    def stub_llm(letter:, follow_ups:, deadlines:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          letter: letter, follow_ups: follow_ups, deadlines: deadlines
        }.to_json } } ] }.to_json
      )
    end
end
