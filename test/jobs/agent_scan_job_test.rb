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

  # A watcher with a bug, standing in for any of them: no sections, so it
  # runs at the Quiet default on the weekly scan.
  class BrokenWatcher
    def self.section_slugs = []
    def initialize(user); end
    def scan = raise "watcher bug"
    def proposals = []
  end

  test "one broken watcher doesn't stop the rest of the scan" do
    with_watchers(BrokenWatcher, Watcher.find!("checkup_cadence")) do
      assert_nothing_raised { AgentScanJob.perform_now(users(:one)) }
    end

    assert_equal 1, users(:one).suggestions.count, "the healthy watcher still ran"

    recorded = AppError.where(error_class: "RuntimeError").sole
    assert_equal "AgentScanJob", recorded.source
    assert_equal users(:one), recorded.user
    assert_equal({ "watcher" => BrokenWatcher.name }, recorded.context)
  end

  # A5 (docs/AGENT_PLAN.md): the greeting stays current for exactly the
  # people who asked the app to be daily.
  test "a user with an Active section gets the digest refreshed daily too" do
    users(:one).user_sections.find_or_initialize_by(section: sections(:health))
      .update!(agent_level: :active, enabled: true)

    assert_difference -> { AppError.count }, 1 do
      AgentScanJob.perform_now(users(:one), cadence: "daily")
    end
  end

  test "a Quiet-only user is not asked for a daily digest" do
    assert_no_difference -> { AppError.count } do
      AgentScanJob.perform_now(users(:one), cadence: "daily")
    end
  end

  test "scan_all fans out one job per user" do
    assert_enqueued_jobs User.count, only: AgentScanJob do
      AgentScanJob.scan_all
    end
  end

  private
    def with_watchers(*watchers)
      original = Watcher.method(:all)
      Watcher.define_singleton_method(:all) { watchers }
      yield
    ensure
      Watcher.define_singleton_method(:all, original)
    end
end
