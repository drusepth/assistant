require "test_helper"

# Comprehension, not diagnosis: the disclaimer and the doctor-questions
# checklist are assembled by code, so the guardrails are assertable without
# trusting model behavior.
class ResultsExplainerToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @results = users(:one).documents.create!(
      title: "Lipid panel",
      extracted_text: "LDL 162 mg/dL (ref < 100, HIGH). HDL 48 mg/dL (ref > 40)."
    )
    @results.sections << sections(:health)
    @run = users(:one).tool_runs.create!(
      tool_slug: "results_explainer",
      inputs: { "document_id" => @results.id.to_s, "question" => "is the LDL number bad?" }
    )
  end

  test "lands one explainer note with the questions checklist and the disclaimer" do
    stub_llm(
      explanation: { title: "Your lipid panel, explained", body: "This is a cholesterol test. The LDL value is marked HIGH against the lab's own range..." },
      questions_for_doctor: [ "Should I repeat this test?", "  ", "Do these results change anything?" ],
      follow_ups: [ { title: "Book the repeat panel the report suggests", due_on: nil } ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    note = @run.items.grep(Note).sole
    assert_equal "Your lipid panel, explained", note.title
    assert_match(/marked HIGH/, note.body)
    assert_match(/Questions for your doctor:\n- Should I repeat this test\?\n- Do these results change anything\?/, note.body)
    assert note.body.end_with?(Tool::ResultsExplainer::DISCLAIMER),
      "the disclaimer is appended by code, never left to the model"
    assert_equal [ sections(:health) ], note.sections

    assert_equal [ "Book the repeat panel the report suggests" ], @run.items.grep(Task).map(&:title)
  end

  test "no questions means no checklist block, and the disclaimer still lands" do
    stub_llm(explanation: { title: nil, body: "Plain reading." }, questions_for_doctor: [], follow_ups: [])

    ToolRunJob.perform_now(@run)

    note = @run.reload.items.grep(Note).sole
    assert_equal "Explained — Lipid panel", note.title
    assert_no_match(/Questions for your doctor/, note.body)
    assert note.body.end_with?(Tool::ResultsExplainer::DISCLAIMER)
  end

  test "follow-ups are capped at two" do
    stub_llm(
      explanation: { title: "t", body: "b" },
      questions_for_doctor: [],
      follow_ups: [ { title: "One" }, { title: "Two" }, { title: "Three" } ]
    )

    ToolRunJob.perform_now(@run)

    assert_equal %w[ One Two ], @run.reload.items.grep(Task).map(&:title)
  end

  test "a missing explanation fails the run" do
    stub_llm(explanation: { title: "x", body: "" }, questions_for_doctor: [], follow_ups: [])

    ToolRunJob.perform_now(@run)

    assert @run.reload.failed?
    assert_match(/didn't return an explanation/, @run.error)
  end

  private
    def stub_llm(explanation:, questions_for_doctor:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          explanation: explanation, questions_for_doctor: questions_for_doctor, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
