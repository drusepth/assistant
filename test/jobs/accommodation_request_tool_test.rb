require "test_helper"

# The interactive-process letter (docs/CAREER.md §3.9): the
# share-only-what's-needed line and the EEOC escalation path are appended
# by code, never left to the model.
class AccommodationRequestToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "drafts the request with the code-appended privacy and escalation footer" do
    run = users(:one).tool_runs.create!(
      tool_slug: "accommodation_request",
      inputs: { "need" => "A stool for register shifts — standing all day aggravates a back injury" }
    )
    stub_llm(
      letter: { title: nil, body: "This letter is a formal request for a reasonable accommodation..." },
      follow_ups: [ { title: "Send to HR with a dated record", due_on: nil } ],
      deadlines: [ { title: "Requested response date", date: 14.days.from_now.to_date.iso8601 } ]
    )

    ToolRunJob.perform_now(run)

    run.reload
    assert run.done?

    letter = run.items.grep(Note).sole
    assert_equal "Accommodation request", letter.title
    assert_includes letter.body, "formal request for a reasonable accommodation"
    assert_includes letter.body, "only enough to establish the need"
    assert_includes letter.body, "retaliation for asking is illegal"
    assert_equal [ sections(:career), sections(:rights) ].sort_by(&:id), letter.sections.sort_by(&:id)
    assert_equal 1, run.items.grep(Event).count

    assert_requested(:post, ENDPOINT) { |request| request.body.include?("stool for register shifts") }
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
