require "test_helper"

# The record generators (D-learning-record): deterministic assembly, landed
# as an owned Document, honest framing on every artifact — and the one
# education tool that must work with no model configured.
class ProgressReportToolTest < ActiveJob::TestCase
  test "a transcript lands as a markdown Document with the evidence trail — no model call anywhere" do
    run = users(:one).tool_runs.create!(
      tool_slug: "progress_report",
      inputs: { "artifact" => "Transcript", "period" => "Everything" }
    )

    ToolRunJob.perform_now(run)

    assert run.reload.done?
    document = run.items.grep(Document).sole
    assert_match(/Transcript — Alice Smith/, document.title)
    assert_match(/not a diploma, and not accreditation/, document.extracted_text)
    assert_match(/Percentages in the wild — mastered/, document.extracted_text)
    assert_match(/retrieval quiz/, document.extracted_text)
    assert document.file.attached?
    assert_equal "text/markdown", document.file.content_type
    assert_includes document.sections.map(&:slug), "education"
  end

  test "the hours log sums the durable study_log lines by month and subject" do
    users(:one).study_logs.create!(subject: subjects(:algebra), on: Date.current, minutes: 45, activity: :tutor)
    users(:one).study_logs.create!(subject: subjects(:algebra), on: Date.current, minutes: 30, activity: :review)
    run = users(:one).tool_runs.create!(
      tool_slug: "progress_report",
      inputs: { "artifact" => "Hours log", "period" => "Everything" }
    )

    ToolRunJob.perform_now(run)

    text = run.reload.items.grep(Document).sole.extracted_text
    assert_match(/Total: 1 h 15 min/, text)
    assert_match(/Everyday math → algebra: 1 h 15 min across 2 sessions/, text)
  end

  test "a portfolio without a working model still builds — the numbers stand alone" do
    sign_out_stub = stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(status: 500, body: "down")
    run = users(:one).tool_runs.create!(
      tool_slug: "progress_report",
      inputs: { "artifact" => "Portfolio", "period" => "Everything" }
    )

    ToolRunJob.perform_now(run)

    document = run.reload.items.grep(Document).sole
    assert_match(/Everyday math/, document.extracted_text)
    assert_requested sign_out_stub, at_least_times: 1
  end
end
