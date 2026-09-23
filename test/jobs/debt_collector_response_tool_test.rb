require "test_helper"

class DebtCollectorResponseToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @notice = users(:one).documents.create!(
      title: "Collection notice",
      extracted_text: "RE: account 4471. Amount due $960. Contact us within 30 days of 2026-08-01."
    )
    @run = users(:one).tool_runs.create!(
      tool_slug: "debt_collector_response",
      inputs: { "document_id" => @notice.id.to_s, "stance" => "I don't recognize this debt" }
    )
  end

  test "drafts the validation letter with the summons warning appended by code" do
    stub_llm(
      letter: { title: "Validation request — account 4471", body: "Pursuant to the FDCPA, I request validation..." },
      follow_ups: [ { title: "Send by certified mail with return receipt", due_on: nil } ],
      deadlines: [ { title: "Validation request deadline — send the letter before this", date: "2026-08-31" } ]
    )

    run_and_add_all(@run)

    @run.reload
    assert @run.done?

    letter = @run.items.grep(Note).sole
    assert_match(/request validation/, letter.body)
    assert_match(/file an answer with the court/, letter.body,
      "the summons warning is a fixed footer, not model behavior")
    assert_includes letter.sections, sections(:disputes)
    assert_includes letter.sections, sections(:debt)

    assert_equal Date.new(2026, 8, 31), @run.items.grep(Event).sole.starts_at.to_date
  end

  test "the footer survives even a minimal model response" do
    stub_llm(letter: { title: nil, body: "To whom it may concern," }, follow_ups: [], deadlines: [])

    run_and_add_all(@run)

    letter = @run.reload.items.grep(Note).sole
    assert letter.body.end_with?(Tool::DebtCollectorResponse::SUMMONS_FOOTER)
    assert_equal "Debt collector response — Collection notice", letter.title
  end

  test "the model call carries the user's stance" do
    stub_llm(letter: { title: "x", body: "y" }, follow_ups: [], deadlines: [])

    run_and_add_all(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("I don't recognize this debt")
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
