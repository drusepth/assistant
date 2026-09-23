require "test_helper"

# The letter family grows into Career (docs/CAREER.md §3.9): a wage demand
# whose escalation footer — state labor agency, free to file, retaliation
# illegal — is appended by code, never left to the model.
class WageClaimToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "drafts the demand from the user's words, footer appended by code" do
    run = users(:one).tool_runs.create!(
      tool_slug: "wage_claim",
      inputs: { "details" => "Three unpaid overtime shifts in June, about $410" }
    )
    stub_llm(
      letter: { title: nil, body: "This letter is a formal demand for unpaid overtime wages..." },
      follow_ups: [ { title: "Send by certified mail", due_on: nil } ],
      deadlines: [ { title: "Response deadline", date: 14.days.from_now.to_date.iso8601 } ]
    )

    run_and_add_all(run)

    run.reload
    assert run.done?

    letter = run.items.grep(Note).sole
    assert_equal "Wage demand letter", letter.title
    assert_includes letter.body, "formal demand for unpaid overtime"
    assert_includes letter.body, "state labor agency takes wage claims at no cost"
    assert_includes letter.body, "retaliation for filing is illegal"
    assert_equal [ sections(:career), sections(:disputes) ].sort_by(&:id), letter.sections.sort_by(&:id)

    assert_equal 1, run.items.grep(Event).count
    assert_equal 1, run.items.grep(Task).count
    assert_requested(:post, ENDPOINT) { |request| request.body.include?("about $410") }
  end

  test "a pay stub joins the prompt and the filing" do
    stub = users(:one).documents.create!(title: "April stub", extracted_text: "80 hours @ $19, gross $1,400")
    stub.sections << sections(:money)
    run = users(:one).tool_runs.create!(
      tool_slug: "wage_claim",
      inputs: { "details" => "gross came up $120 short", "document_id" => stub.id.to_s }
    )
    stub_llm(letter: { title: "Demand", body: "..." }, follow_ups: [], deadlines: [])

    run_and_add_all(run)

    letter = run.reload.items.grep(Note).sole
    assert_includes letter.sections, sections(:money)
    assert_requested(:post, ENDPOINT) { |request| request.body.include?("April stub") }
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
