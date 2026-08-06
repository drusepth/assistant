require "test_helper"

class CancelSubscriptionToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "cancel_subscription",
      inputs: { "service" => "Planet Gym membership", "details" => "renews on the 1st, $45/mo" }
    )
  end

  test "lands the letter with the phone script in one note, plus the statement-check follow-up" do
    stub_llm(
      letter: { title: "Cancellation request — Planet Gym", body: "This letter is a formal request to cancel..." },
      script: "Hi, I'm calling to cancel my membership. No thank you, please just process the cancellation.",
      follow_ups: [
        { title: "Submit the cancellation", due_on: Date.current.iso8601 },
        { title: "Check next statement for charges", due_on: 30.days.from_now.to_date.iso8601 }
      ],
      deadlines: [ { title: "Cancel before the renewal", date: "2026-09-01" } ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    note = @run.items.grep(Note).sole
    assert_match(/formal request to cancel/, note.body)
    assert_match(/If you have to call:\nHi, I'm calling to cancel/, note.body)
    assert_equal [ sections(:subscriptions) ], note.sections

    assert_equal Date.new(2026, 9, 1), @run.items.grep(Event).sole.starts_at.to_date
    assert_includes @run.items.grep(Task).map(&:title), "Check next statement for charges"
  end

  test "no script means the letter stands alone, and no document is required" do
    stub_llm(letter: { title: nil, body: "Please cancel my account." }, script: nil, follow_ups: [], deadlines: [])

    ToolRunJob.perform_now(@run)

    note = @run.reload.items.grep(Note).sole
    assert_equal "Cancellation request — Planet Gym membership", note.title
    assert_no_match(/If you have to call/, note.body)
    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("renews on the 1st") && !request.body.include?("The document (titled")
    end
  end

  private
    def stub_llm(letter:, script:, follow_ups:, deadlines:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          letter: letter, script: script, follow_ups: follow_ups, deadlines: deadlines
        }.to_json } } ] }.to_json
      )
    end
end
