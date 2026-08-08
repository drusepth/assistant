require "test_helper"

class CheckPayStubToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "lands the explanation with the app-checked numbers block and routes short pay to the wage claim" do
    stub = users(:one).documents.create!(
      title: "April stub", extracted_text: "ACME LOGISTICS — 80 hours @ $19.00, gross $1,400.00",
      extracted_facts: { "pay_stub" => { "rate" => "19", "hours" => "80", "gross" => "1400" } }
    )
    run = users(:one).tool_runs.create!(tool_slug: "check_pay_stub", inputs: { "document_id" => stub.id.to_s })
    stub_llm(explanation: { title: "Your April stub, explained", body: "Gross is what you earned before anything came out..." })

    ToolRunJob.perform_now(run)

    run.reload
    assert run.done?

    note = run.items.grep(Note).sole
    assert_includes note.body, "What the numbers say (checked by the app, not the AI):"
    assert_includes note.body, "$120.00 missing"

    next_tool = run.output["next_tools"].sole
    assert_equal "wage_claim", next_tool["slug"]
    assert_equal stub.id.to_s, next_tool.dig("inputs", "document_id")
    assert_match(/missing/, next_tool.dig("inputs", "details"))
  end

  test "a clean stub gets no numbers block and no routing" do
    stub = users(:one).documents.create!(
      title: "April stub", extracted_text: "80 hours @ $19.00, gross $1,520.00",
      extracted_facts: { "pay_stub" => { "rate" => "19", "hours" => "80", "gross" => "1520" } }
    )
    run = users(:one).tool_runs.create!(tool_slug: "check_pay_stub", inputs: { "document_id" => stub.id.to_s })
    stub_llm(explanation: { title: "t", body: "b" })

    ToolRunJob.perform_now(run)

    run.reload
    assert run.done?
    assert_not_includes run.items.grep(Note).sole.body, "What the numbers say"
    assert_nil run.output["next_tools"]
  end

  test "the previous stub's facts join the prompt for the why-did-net-move story" do
    users(:one).documents.create!(title: "March stub",
      extracted_facts: { "pay_stub" => { "rate" => "19", "net" => "1201.33", "pay_date" => "2026-03-15" } })
    stub = users(:one).documents.create!(
      title: "April stub", extracted_text: "gross $1,520.00, net $1,150.10",
      extracted_facts: { "pay_stub" => { "rate" => "19", "net" => "1150.10", "pay_date" => "2026-04-15" } }
    )
    run = users(:one).tool_runs.create!(tool_slug: "check_pay_stub", inputs: { "document_id" => stub.id.to_s })
    stub_llm(explanation: { title: "t", body: "b" })

    ToolRunJob.perform_now(run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("previous stub (2026-03-15)") && request.body.include?("net: 1201.33")
    end
  end

  test "an unanalyzed stub still gets the plain-language walkthrough, just no numbers block" do
    stub = users(:one).documents.create!(title: "Paper stub", extracted_text: "Gross $1,400, net $1,100.")
    run = users(:one).tool_runs.create!(tool_slug: "check_pay_stub", inputs: { "document_id" => stub.id.to_s })
    stub_llm(explanation: { title: "t", body: "the walkthrough" })

    ToolRunJob.perform_now(run)

    run.reload
    assert run.done?
    assert_equal "the walkthrough", run.items.grep(Note).sole.body
  end

  private
    def stub_llm(explanation:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          explanation: explanation, follow_ups: []
        }.to_json } } ] }.to_json
      )
    end
end
