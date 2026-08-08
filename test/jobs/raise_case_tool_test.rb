require "test_helper"

# The win log and comp timeline paying out (docs/CAREER.md §3.4): tenure
# math computed by code, receipts from the tracked record, market numbers
# as a fetch-list — never invented.
class RaiseCaseToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "lands the memo with code-computed tenure and the research block, routed to negotiation prep" do
    travel_to Date.new(2026, 8, 8) do
      Career::CompChange.log!(user: users(:one), summary: "Raise: $19 → $21/hr", on: Date.new(2025, 2, 1))
      Career::WinLog.log!(user: users(:one), text: "Caught the inventory error before the audit")
      run = users(:one).tool_runs.create!(tool_slug: "raise_case", inputs: { "extras" => "took over scheduling in May" })
      stub_llm(
        memo: { title: "Raise case — August 2026", body: "My pay was last adjusted 18 months ago..." },
        research: [ "BLS wage table for warehouse supervisors in your metro" ],
        follow_ups: [ { title: "Fetch the BLS number", due_on: nil } ]
      )

      ToolRunJob.perform_now(run)

      run.reload
      assert run.done?

      note = run.items.grep(Note).sole
      assert_includes note.body, "Numbers to fetch before the ask:\n- BLS wage table"
      assert_equal [ sections(:career) ], note.sections.to_a

      assert_equal "negotiation_prep", run.output["next_tools"].sole["slug"]

      assert_requested(:post, ENDPOINT) do |request|
        request.body.include?("pay last changed on 2025-02-01 — 18 months ago") &&
          request.body.include?("took over scheduling in May") &&
          request.body.include?("Caught the inventory error")
      end
    end
  end

  test "with no comp timeline the tenure fact becomes a placeholder instruction" do
    run = users(:one).tool_runs.create!(tool_slug: "raise_case", inputs: {})
    stub_llm(memo: { title: "t", body: "b" }, research: [], follow_ups: [])

    ToolRunJob.perform_now(run)

    assert run.reload.done?
    assert_requested(:post, ENDPOINT) { |request| request.body.include?("No pay change is recorded") }
  end

  private
    def stub_llm(memo:, research:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          memo: memo, research: research, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
