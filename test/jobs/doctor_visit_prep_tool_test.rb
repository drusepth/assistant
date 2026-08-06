require "test_helper"

# The first tool that reads a section rather than a document: the prompt
# carries the user's Health-tagged data — and nothing anyone else kept
# private.
class DoctorVisitPrepToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "doctor_visit_prep",
      inputs: { "reason" => "annual physical" }
    )
  end

  test "builds the visit sheet from Health-tagged data, questions and footer assembled by code" do
    journal = users(:one).notes.create!(title: "Symptoms", body: "Occasional dizziness since May")
    journal.sections << sections(:health)
    private_note = users(:two).notes.create!(body: "Bob's private diagnosis")
    private_note.sections << sections(:health)

    stub_llm(
      prep: { title: "Visit sheet — annual physical", body: "Reason: annual physical.\n2026-05 — dizziness reported..." },
      questions: [ "Could the dizziness be blood-pressure related?" ],
      follow_ups: [ { title: "Write down current medications", due_on: nil } ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Occasional dizziness since May") &&
        !request.body.include?("Bob's private diagnosis")
    end

    sheet = @run.items.grep(Note).sole
    assert_match(/Questions to ask:\n- Could the dizziness/, sheet.body)
    assert sheet.body.end_with?(Tool::DoctorVisitPrep::FOOTER)
    assert_equal [ sections(:health) ], sheet.sections

    assert_equal [ "Write down current medications" ], @run.items.grep(Task).map(&:title)
  end

  test "an empty Health section still produces a sheet, from the reason alone" do
    stub_llm(prep: { title: nil, body: "Reason: annual physical. [CURRENT MEDICATIONS]" }, questions: [], follow_ups: [])

    ToolRunJob.perform_now(@run)

    assert @run.reload.done?
    assert_equal "Visit sheet — annual physical", @run.items.grep(Note).sole.title
    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("No tracked health data yet")
    end
  end

  test "a missing sheet fails the run" do
    stub_llm(prep: { title: "x", body: "" }, questions: [], follow_ups: [])

    ToolRunJob.perform_now(@run)

    assert @run.reload.failed?
    assert_match(/didn't return a visit sheet/, @run.error)
  end

  private
    def stub_llm(prep:, questions:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          prep: prep, questions: questions, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
