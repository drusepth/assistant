require "test_helper"

# The Q9-honest meetup tool: a where-to-look guide plus check-this-week
# tasks — no live listings, no invented local clubs.
class FindYourPeopleToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @lens = Hobbies::Lens.find_or_create!("Climbing")
    @run = users(:one).tool_runs.create!(
      tool_slug: "find_your_people",
      inputs: { "hobby" => "Climbing", "area" => "Tulsa" }
    )
  end

  test "lands a guide note and follow-up tasks filed under the hobby" do
    stub_llm(
      draft: { title: "Finding climbing people in Tulsa", body: "Where climbers gather:\n- Search Meetup for climbing groups" },
      follow_ups: [
        { title: "Check Meetup for climbing groups this week", due_on: Date.current.iso8601 },
        { title: "Ask at the local gym about intro nights", due_on: nil }
      ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    note = @run.items.grep(Note).sole
    assert_equal "Finding climbing people in Tulsa", note.title
    assert_includes note.sections, sections(:hobbies)
    assert_includes note.sections, @lens

    tasks = @run.items.grep(Task).sort_by(&:id)
    assert_equal 3, tasks.count
    assert tasks.first.today?
    assert tasks.second.later?
    assert_includes tasks.first.sections, @lens

    # The listings half arrived without Q9 (docs/EVENT_RADAR_PLAN.md): one
    # deterministic follow-up points at Places, and still names no club.
    follow = tasks.last
    assert_equal "Follow the calendars where Climbing people gather", follow.title
    assert_match "add Tulsa", follow.notes
    assert_match "/places", follow.notes
  end

  test "the model call carries the hobby, the area, and the lens's notes" do
    note = users(:one).notes.create!(title: "Level", body: "Bouldering V2, never climbed outdoors")
    note.sections = [ @lens ]
    stub_llm(draft: { title: "t", body: "b" }, follow_ups: [])

    ToolRunJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Climbing") && request.body.include?("Tulsa") &&
        request.body.include?("never climbed outdoors")
    end
  end

  test "at most three follow-ups are created" do
    stub_llm(
      draft: { title: "t", body: "b" },
      follow_ups: (1..5).map { |n| { title: "Task #{n}", due_on: nil } }
    )

    ToolRunJob.perform_now(@run)

    # Three from the model, plus the one deterministic Places follow-up.
    assert_equal 4, @run.reload.items.grep(Task).count
  end

  test "a missing guide fails the run with a friendly error" do
    stub_llm(draft: { title: "t", body: "" }, follow_ups: [])

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.failed?
    assert_match "try again", @run.error
    assert_empty @run.items
  end

  test "a free-typed hobby with no lens files under Hobbies alone and creates no lens" do
    run = users(:one).tool_runs.create!(
      tool_slug: "find_your_people", inputs: { "hobby" => "Fencing" }
    )
    stub_llm(draft: { title: "t", body: "b" }, follow_ups: [])

    assert_no_difference "Section.count" do
      ToolRunJob.perform_now(run)
    end

    note = run.reload.items.grep(Note).sole
    assert_equal [ sections(:hobbies) ], note.sections.to_a
  end

  private
    def stub_llm(draft:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          draft: draft, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
