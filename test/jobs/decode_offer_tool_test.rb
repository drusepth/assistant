require "test_helper"

class DecodeOfferToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "lands the decoded offer with flags and questions, the deadline on the calendar, and the counter routed" do
    offer = users(:one).documents.create!(title: "Acme offer",
      extracted_text: "Base $58,000. Non-compete: 18 months. Offer expires August 20, 2026.")
    offer.sections << sections(:career)
    run = users(:one).tool_runs.create!(tool_slug: "decode_offer", inputs: { "document_id" => offer.id.to_s })
    stub_llm(
      decoded: { title: "The Acme offer, decoded", body: "Base salary is $58,000..." },
      red_flags: [ "An 18-month non-compete restricts where you can work next [verify for your state]." ],
      questions: [ "Will you strike or narrow the non-compete?" ],
      deadlines: [ { title: "Acme offer expires", date: "2026-08-20" } ],
      follow_ups: [ { title: "Decide before the deadline", due_on: "2026-08-19" } ]
    )

    run_and_add_all(run)

    run.reload
    assert run.done?

    note = run.items.grep(Note).sole
    assert_includes note.body, "Red flags to weigh:\n- An 18-month non-compete"
    assert_includes note.body, "Ask before signing:\n- Will you strike"

    event = run.items.grep(Event).sole
    assert_equal "Acme offer expires", event.title
    assert event.all_day

    next_tool = run.output["next_tools"].sole
    assert_equal "negotiation_prep", next_tool["slug"]
    assert_equal offer.id.to_s, next_tool.dig("inputs", "document_id")
  end

  test "a missing decode fails the run with a friendly message" do
    offer = users(:one).documents.create!(title: "Offer", extracted_text: "words")
    run = users(:one).tool_runs.create!(tool_slug: "decode_offer", inputs: { "document_id" => offer.id.to_s })
    stub_llm(decoded: { title: nil, body: nil }, red_flags: [], questions: [], deadlines: [], follow_ups: [])

    run_and_add_all(run)

    assert run.reload.failed?
    assert_match(/couldn't decode/, run.error)
  end

  private
    def stub_llm(decoded:, red_flags:, questions:, deadlines:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          decoded: decoded, red_flags: red_flags, questions: questions,
          deadlines: deadlines, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
