require "test_helper"

class NegotiationPrepToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "lands the prep sheet and the counter-message as two separate notes" do
    run = users(:one).tool_runs.create!(
      tool_slug: "negotiation_prep",
      inputs: { "scenario" => "salary offer from Acme", "constraints" => "target $85k" }
    )
    stub_llm(
      prep: { title: "Negotiating the Acme offer", body: "Your leverage: the offer in hand..." },
      counter_message: { title: "Counter-offer email", body: "Thank you for the offer. Based on [MARKET RATE]..." },
      follow_ups: [ { title: "Look up the market rate for the role", due_on: nil } ]
    )

    run_and_add_all(run)

    run.reload
    assert run.done?

    notes = run.items.grep(Note)
    assert_equal [ "Negotiating the Acme offer", "Counter-offer email" ], notes.map(&:title)
    notes.each do |note|
      assert_equal [ sections(:career), sections(:renting), sections(:bills) ].sort_by(&:id),
        note.sections.sort_by(&:id)
    end

    assert_requested(:post, ENDPOINT) { |request| request.body.include?("target $85k") }
  end

  test "a chosen document joins the prompt and its sections join the filing" do
    offer = users(:one).documents.create!(title: "Acme offer letter", extracted_text: "Base salary: $78,000")
    offer.sections << sections(:career)
    run = users(:one).tool_runs.create!(
      tool_slug: "negotiation_prep",
      inputs: { "scenario" => "salary offer", "document_id" => offer.id.to_s }
    )
    stub_llm(prep: { title: "t", body: "b" }, counter_message: nil, follow_ups: [])

    run_and_add_all(run)

    assert run.reload.done?
    assert_equal 1, run.items.grep(Note).count, "no counter-message returned, no empty note forced"
    assert_requested(:post, ENDPOINT) { |request| request.body.include?("$78,000") }
  end

  test "a missing prep sheet fails the run" do
    run = users(:one).tool_runs.create!(tool_slug: "negotiation_prep", inputs: { "scenario" => "rent" })
    stub_llm(prep: { title: nil, body: nil }, counter_message: nil, follow_ups: [])

    run_and_add_all(run)

    assert run.reload.failed?
    assert_match(/didn't return a prep sheet/, run.error)
  end

  private
    def stub_llm(prep:, counter_message:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          prep: prep, counter_message: counter_message, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
