require "test_helper"

class AgentScanJobTest < ActiveJob::TestCase
  # The weekly scan also attempts the phrased digest; a failing provider
  # must never break the deterministic half.
  setup do
    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(status: 500, body: "down")
  end

  test "a failed digest stays silent for the user but reaches the error log" do
    assert_difference -> { AppError.count }, 1 do
      AgentScanJob.perform_now(users(:one))
    end

    recorded = AppError.recent.first
    assert_equal "AgentScanJob", recorded.source
    assert_equal users(:one), recorded.user
    assert_equal 1, users(:one).suggestions.count, "the deterministic half still ran"
  end

  test "scans every watcher for the user" do
    AgentScanJob.perform_now(users(:one))

    assert_equal 1, users(:one).suggestions.count
    assert_equal "checkup_cadence", users(:one).suggestions.sole.watcher_slug
  end

  test "a watcher on a disabled section stays silent" do
    users(:one).user_sections.create!(section: sections(:health), enabled: false)

    AgentScanJob.perform_now(users(:one))

    assert_empty users(:one).suggestions
  end

  test "scan_all fans out one job per user" do
    assert_enqueued_jobs User.count, only: AgentScanJob do
      AgentScanJob.scan_all
    end
  end
end
