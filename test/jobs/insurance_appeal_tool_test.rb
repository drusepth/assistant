require "test_helper"

# The first letter-family tool to land deadlines as calendar Events — the
# appeal window is the whole point.
class InsuranceAppealToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @denial = users(:one).documents.create!(
      title: "Claim denial",
      extracted_text: "Claim 998-A for the 2026-06-12 MRI is denied: not medically necessary. Appeals accepted within 180 days."
    )
    @denial.sections << sections(:health)
    @run = users(:one).tool_runs.create!(
      tool_slug: "insurance_appeal",
      inputs: { "document_id" => @denial.id.to_s, "intent" => "my doctor ordered the MRI" }
    )
  end

  test "drafts the appeal, schedules follow-ups, and puts the deadline on the calendar" do
    deadline = 150.days.from_now.to_date
    stub_llm(
      letter: { title: "Appeal of claim 998-A", body: "I am writing to formally appeal..." },
      follow_ups: [ { title: "Send the appeal by certified mail", due_on: Date.current.iso8601 } ],
      deadlines: [ { title: "Appeal filing deadline", date: deadline.iso8601 } ]
    )

    run_and_add_all(@run)

    @run.reload
    assert @run.done?

    letter = @run.items.grep(Note).sole
    assert_equal "Appeal of claim 998-A", letter.title
    assert_equal [ sections(:health), sections(:disputes) ].sort_by(&:id), letter.sections.sort_by(&:id),
      "filed where the tool lives plus the denial's own sections"

    event = @run.items.grep(Event).sole
    assert_equal "Appeal filing deadline", event.title
    assert event.all_day?
    assert_equal deadline, event.starts_at.to_date
    assert_equal letter.sections.sort_by(&:id), event.sections.sort_by(&:id)

    task = @run.items.grep(Task).sole
    assert task.today?, "a follow-up due today lands in the Today column"
  end

  test "malformed or dateless deadlines are dropped, never invented" do
    stub_llm(
      letter: { title: nil, body: "Dear appeals department," },
      follow_ups: [],
      deadlines: [ { title: "No date given" }, { title: "Bad date", date: "someday" }, "not a hash" ]
    )

    run_and_add_all(@run)

    assert @run.reload.done?
    assert_empty @run.items.grep(Event)
    assert_equal "Appeal letter — Claim denial", @run.items.grep(Note).sole.title
  end

  test "the model call carries the user's intent and the denial text" do
    stub_llm(letter: { title: "x", body: "y" }, follow_ups: [], deadlines: [])

    run_and_add_all(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("my doctor ordered the MRI") && request.body.include?("998-A")
    end
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
