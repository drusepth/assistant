require "test_helper"

# Reads a Person into a ready-to-send opener plus grounded talking points.
# Seeds the M3 stay-in-touch watcher: its accept action runs this prefilled.
class ReconnectToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @mom = users(:one).people.create!(
      name: "Rosa", relationship: "Mom", birthday: Date.new(1958, 9, 12),
      notes: "Just moved to the coast; started painting again."
    )
    @mom.sections << sections(:people)
    @run = users(:one).tool_runs.create!(
      tool_slug: "reconnect",
      inputs: { "person_id" => @mom.id.to_s, "occasion" => "her birthday's coming up" }
    )
  end

  test "lands the message with talking points, grounded in the person's record" do
    stub_llm(
      message: { title: "A birthday hello for Rosa", body: "Hi Mom — been thinking of you with your birthday coming up..." },
      talking_points: [ "Ask how the new place by the coast feels", "Ask what she's been painting" ],
      follow_ups: [ { title: "Send the message", due_on: Date.current.iso8601 } ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    note = @run.items.grep(Note).sole
    assert_equal "A birthday hello for Rosa", note.title
    assert_match(/Talking points:\n- Ask how the new place/, note.body)
    assert_equal [ sections(:people) ], note.sections

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Relationship: Mom") &&
        request.body.include?("started painting again") &&
        request.body.include?("1958-09-12") &&
        request.body.include?("her birthday's coming up")
    end
  end

  test "a fallback title names the person" do
    stub_llm(message: { title: nil, body: "Hey!" }, talking_points: [], follow_ups: [])

    ToolRunJob.perform_now(@run)

    assert_equal "Reconnect with Rosa", @run.reload.items.grep(Note).sole.title
  end

  test "a vanished person fails the run without calling the model" do
    @mom.destroy!

    ToolRunJob.perform_now(@run)

    assert @run.reload.failed?
    assert_match(/gone or no longer shared/, @run.error)
    assert_not_requested :post, ENDPOINT
  end

  private
    def stub_llm(message:, talking_points:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          message: message, talking_points: talking_points, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
