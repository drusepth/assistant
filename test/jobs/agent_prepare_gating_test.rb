require "test_helper"

# Preparation is the first thing the agent spends model tokens on without
# being asked, so what stops it matters as much as what it does
# (D-agent-prepared-work): the Active dial, the user's switch, a configured
# model, and a hard per-scan budget.
class AgentPrepareGatingTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(status: 500, body: "down")
  end

  # A watcher that proposes as many preparable suggestions as asked for,
  # standing in for any Active-dial watcher on a busy week.
  class ProposingWatcher < Watcher::Base
    self.section_slugs = %w[ health ]
    cattr_accessor :count, default: 1

    def scan
      count.times do |n|
        propose(fingerprint: "n#{n}", title: "Find a dentist #{n}",
          action: { "tool" => { "slug" => "find_care", "inputs" => { "specialty" => "dentist" } } })
      end
    end
  end

  test "an Active section prepares, up to the budget" do
    ProposingWatcher.count = AgentScanJob::PREPARE_BUDGET + 2
    dial(:active)

    with_watchers(ProposingWatcher) do
      assert_enqueued_jobs AgentScanJob::PREPARE_BUDGET, only: AgentPrepareJob do
        AgentScanJob.perform_now(@user, cadence: "daily")
      end
    end
  end

  test "a Quiet section prepares nothing" do
    # Quiet means in-app and unhurried; drafting ahead is what the louder
    # dial buys, so nothing here changes for the default user.
    ProposingWatcher.count = 1
    dial(:quiet)

    with_watchers(ProposingWatcher) do
      assert_no_enqueued_jobs only: AgentPrepareJob do
        AgentScanJob.perform_now(@user)
      end
    end
  end

  test "the user's switch stops it" do
    ProposingWatcher.count = 1
    dial(:active)
    @user.update!(prepare_work: false)

    with_watchers(ProposingWatcher) do
      assert_no_enqueued_jobs only: AgentPrepareJob do
        AgentScanJob.perform_now(@user, cadence: "daily")
      end
    end

    assert_equal 1, @user.suggestions.count, "the suggestion itself still arrives"
  end

  test "with no model configured the feature silently does not exist" do
    ProposingWatcher.count = 1
    dial(:active)
    @user.household.model_profile&.update!(api_key: nil)

    with_watchers(ProposingWatcher) do
      assert_no_enqueued_jobs only: AgentPrepareJob do
        assert_nothing_raised { AgentScanJob.perform_now(@user, cadence: "daily") }
      end
    end
  end

  test "suggestions with nothing to prepare are skipped without spending budget" do
    dial(:active)

    with_watchers(Watcher.find!("stale_task")) do
      @user.tasks.create!(title: "Undated and old", bucket: :later, created_at: 6.weeks.ago)
      assert_no_enqueued_jobs only: AgentPrepareJob do
        AgentScanJob.perform_now(@user, cadence: "daily")
      end
    end
  end

  private
    def dial(level)
      Section.top_level.each do |section|
        @user.user_sections.find_or_initialize_by(section: section).update!(agent_level: level, enabled: true)
      end
    end

    def with_watchers(*watchers)
      original = Watcher.method(:all)
      Watcher.define_singleton_method(:all) { watchers }
      yield
    ensure
      Watcher.define_singleton_method(:all, original)
    end
end
