require "test_helper"

# The universal front door (D28): decode any scary mail, put its deadlines
# on the calendar, and offer the specialized response tool prefilled. The
# model proposes routes; code sanitizes them.
class DecodeLetterToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @letter = users(:one).documents.create!(
      title: "Scary envelope",
      extracted_text: "Your claim 12-B has been denied as not medically necessary. You have 180 days to appeal."
    )
    @letter.sections << sections(:health)
    @run = users(:one).tool_runs.create!(
      tool_slug: "decode_letter",
      inputs: { "document_id" => @letter.id.to_s }
    )
  end

  test "decodes the letter, files it by triage, calendars the deadline, and routes to the specialist" do
    stub_llm(
      decoded: { title: "This is an insurance denial", body: "Your insurer is refusing to pay for..." },
      sections: %w[ disputes money ],
      deadlines: [ { title: "Appeal window closes", date: "2027-02-01" } ],
      follow_ups: [ { title: "Find the plan's appeals address", due_on: nil } ],
      next_tools: [ { slug: "insurance_appeal", reason: "This is an appealable denial.",
                      inputs: { intent: "the treatment was medically necessary" } } ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    note = @run.items.grep(Note).sole
    assert_equal "This is an insurance denial", note.title
    assert_equal [ sections(:health), sections(:disputes), sections(:money) ].sort_by(&:id),
      note.sections.sort_by(&:id),
      "filed under the document's sections plus the model's triage — not the tool's three registration sections"

    assert_equal Date.new(2027, 2, 1), @run.items.grep(Event).sole.starts_at.to_date

    step = @run.next_steps.sole
    assert_equal Tool::InsuranceAppeal, step.tool
    assert_equal "This is an appealable denial.", step.reason
    assert_equal @letter.id.to_s, step.inputs["document_id"], "code attaches the document, not the model"
    assert_equal "the treatment was medically necessary", step.inputs["intent"]
  end

  test "routing proposals are sanitized: unknown slugs, unallowed tools, and undeclared inputs are dropped" do
    stub_llm(
      decoded: { title: "t", body: "b" },
      sections: [],
      deadlines: [],
      follow_ups: [],
      next_tools: [
        { slug: "rm_rf", reason: "nope" },
        { slug: "learn_something", reason: "registered but not routable from here" },
        { slug: "debt_collector_response", reason: "keep me",
          inputs: { stance: "not my debt", sneaky_field: "dropped", document_id: "999" } },
        { slug: "debt_collector_response", reason: "duplicate slug, dropped" },
        { slug: "dispute_letter", reason: "third distinct tool, over the cap" }
      ]
    )

    ToolRunJob.perform_now(@run)

    steps = @run.reload.next_steps
    assert_equal [ Tool::DebtCollectorResponse, Tool::DisputeLetter ], steps.map(&:tool),
      "two survivors — the cap is #{Tool::Base::MAX_NEXT_TOOLS}"
    assert_equal @letter.id.to_s, steps.first.inputs["document_id"],
      "even a model-invented document_id is overwritten with the real one"
    assert_equal "not my debt", steps.first.inputs["stance"]
    assert_nil steps.first.inputs["sneaky_field"]
  end

  test "mail that needs no response stores no next steps" do
    stub_llm(decoded: { title: "Just a receipt", body: "Nothing to do." },
      sections: [], deadlines: [], follow_ups: [], next_tools: [])

    ToolRunJob.perform_now(@run)

    @run.reload
    assert_empty @run.next_steps
    assert_not @run.output.key?("next_tools")
  end

  test "the prompt carries the taxonomy, the tool catalog, and the letter" do
    stub_llm(decoded: { title: "t", body: "b" }, sections: [], deadlines: [], follow_ups: [], next_tools: [])

    ToolRunJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("insurance_appeal") &&
        request.body.include?("disputes") &&
        request.body.include?("claim 12-B")
    end
  end

  private
    def stub_llm(decoded:, sections:, deadlines:, follow_ups:, next_tools:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          decoded: decoded, sections: sections, deadlines: deadlines,
          follow_ups: follow_ups, next_tools: next_tools
        }.to_json } } ] }.to_json
      )
    end
end
