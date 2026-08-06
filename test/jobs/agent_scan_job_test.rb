require "test_helper"

class AgentScanJobTest < ActiveJob::TestCase
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
