require "test_helper"

# D33 (resolving Q13): chat transcripts are working data; recaps are the
# record. Idle chat runs are deleted whole — their recap Notes live on.
class PruneChatTranscriptsJobTest < ActiveJob::TestCase
  test "prunes idle chat runs, keeps recent ones, drafts, and recap notes" do
    stale = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done, created_at: 4.months.ago)
    stale.tool_run_messages.create!(role: :assistant, content: "Hi", created_at: 4.months.ago)
    recap = users(:one).notes.create!(title: "Check-in recap", body: "What came up.")
    stale.tool_run_items.create!(item: recap)

    active = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "math" }, status: :done, created_at: 4.months.ago)
    active.tool_run_messages.create!(role: :assistant, content: "Welcome back", created_at: 1.week.ago)

    draft = users(:one).tool_runs.create!(tool_slug: "find_care", inputs: { "specialty" => "dentist" }, status: :done, created_at: 4.months.ago)

    PruneChatTranscriptsJob.perform_now

    assert_not ToolRun.exists?(stale.id), "an idle chat run is deleted whole"
    assert Note.exists?(recap.id), "the recap is the durable artifact"
    assert ToolRun.exists?(active.id), "a chat with recent messages stays"
    assert ToolRun.exists?(draft.id), "draft runs are history, never pruned"
  end
end
