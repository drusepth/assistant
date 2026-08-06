require "test_helper"

class ToolRunJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @document = users(:one).documents.create!(
      title: "Hospital bill",
      extracted_text: "Amount due: $2,400. Account 12345. Statement date: 2026-07-20."
    )
    @document.sections << sections(:health)
    @run = users(:one).tool_runs.create!(
      tool_slug: "dispute_letter",
      inputs: { "document_id" => @document.id.to_s, "intent" => "this charge is wrong" }
    )
  end

  test "drafts the letter as a filed note, adds follow-ups, and finishes the run" do
    stub_llm(
      letter: { title: "Dispute of account 12345", body: "To whom it may concern,\n\nI dispute..." },
      follow_ups: [
        { title: "Mail the letter", due_on: Date.current.iso8601 },
        { title: "Chase a reply if silent for 30 days", due_on: nil }
      ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?
    assert_nil @run.error

    letter = @run.items.grep(Note).first
    assert_equal "Dispute of account 12345", letter.title
    assert_match(/I dispute/, letter.body)
    assert_equal [ sections(:disputes), sections(:health) ].sort_by(&:id), letter.sections.sort_by(&:id),
      "the letter is filed where the tool lives plus the document's own sections"

    tasks = @run.items.grep(Task).sort_by(&:id)
    assert_equal [ "Mail the letter", "Chase a reply if silent for 30 days" ], tasks.map(&:title)
    assert tasks.first.today?, "a follow-up due today lands in the Today column"
    assert tasks.second.later?
  end

  test "a letter without a title falls back to the document's" do
    stub_llm(letter: { title: nil, body: "Dear billing office," }, follow_ups: [])

    ToolRunJob.perform_now(@run)

    assert_equal "Dispute letter — Hospital bill", @run.items.grep(Note).first.title
  end

  test "provider errors fail the run with a friendly message" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.failed?
    assert_match(/model provider returned 500/, @run.error)
    assert_empty @run.items
  end

  test "a missing letter body fails the run" do
    stub_llm(letter: { title: "x", body: "" }, follow_ups: [])

    ToolRunJob.perform_now(@run)

    assert @run.reload.failed?
    assert_match(/didn't return a letter/, @run.error)
  end

  test "a vanished document fails the run without calling the model" do
    @document.destroy!

    ToolRunJob.perform_now(@run)

    assert @run.reload.failed?
    assert_match(/gone or no longer shared/, @run.error)
    assert_not_requested :post, ENDPOINT
  end

  test "a document with no readable text fails with a pointer to Analyze" do
    @document.update!(extracted_text: nil, summary: nil)

    ToolRunJob.perform_now(@run)

    assert @run.reload.failed?
    assert_match(/run Analyze first/, @run.error)
  end

  test "a household without a configured model fails the run gracefully" do
    document = users(:outsider).documents.create!(title: "Bill", extracted_text: "text")
    run = users(:outsider).tool_runs.create!(tool_slug: "dispute_letter", inputs: { "document_id" => document.id.to_s })

    ToolRunJob.perform_now(run)

    assert run.reload.failed?
    assert_match(/need an AI model/, run.error)
    assert_not_requested :post, ENDPOINT
  end

  private
    def stub_llm(letter:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          letter: letter, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
