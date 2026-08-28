require "test_helper"

# The suggestion lifecycle (D-suggestion-lifecycle): a nudge the world has
# handled retires itself, rather than waiting in Attend for a dismissal it
# no longer deserves. `resolved` is deliberately distinct from `dismissed` —
# "you handled it" and "I didn't want this" are opposite signals.
class AgentRetireTest < ActiveJob::TestCase
  setup do
    # The weekly scan attempts the phrased digest; the retire pass must not
    # depend on a reachable provider.
    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(status: 500, body: "down")
    @user = users(:one)
  end

  test "a suggestion whose date has passed retires with no watcher involvement" do
    suggestion = propose(action: { "expires_on" => 1.day.ago.to_date.iso8601 })

    AgentScanJob.perform_now(@user)

    assert_predicate suggestion.reload, :resolved?
  end

  test "a suggestion whose date is still ahead stays put" do
    suggestion = propose(action: { "expires_on" => 3.days.from_now.to_date.iso8601 })

    AgentScanJob.perform_now(@user)

    assert_predicate suggestion.reload, :pending?
  end

  test "expiry retires even in a section the user has turned off" do
    # Cleaning up a stale row is not the agent speaking, so it is not gated
    # on the dial that decides whether the agent may speak.
    @user.user_sections.create!(section: sections(:health), enabled: false)
    suggestion = propose(action: { "expires_on" => 1.day.ago.to_date.iso8601 }, sections: [ sections(:health) ])

    AgentScanJob.perform_now(@user)

    assert_predicate suggestion.reload, :resolved?
  end

  test "a garbled expires_on is ignored rather than fatal" do
    suggestion = propose(action: { "expires_on" => "soon-ish" })

    assert_nothing_raised { AgentScanJob.perform_now(@user) }
    assert_predicate suggestion.reload, :pending?
  end

  test "an accepted suggestion is left alone" do
    suggestion = propose(action: { "expires_on" => 1.day.ago.to_date.iso8601 })
    suggestion.update!(status: :accepted)

    AgentScanJob.perform_now(@user)

    assert_predicate suggestion.reload, :accepted?, "retirement only ever touches live suggestions"
  end

  # ── The watcher-answered half ─────────────────────────────────────────

  test "a stale-task nudge retires once the task has a date" do
    task = @user.tasks.create!(title: "Fix the gutter", bucket: :later, created_at: 6.weeks.ago)
    suggestion = propose(watcher_slug: "stale_task", fingerprint: "stale_task/task:#{task.id}/x",
      action: { "schedule_task" => { "id" => task.id } })

    task.update!(due_on: Date.current)
    AgentScanJob.perform_now(@user)

    assert_predicate suggestion.reload, :resolved?
  end

  test "a stale-task nudge retires when the task is deleted" do
    task = @user.tasks.create!(title: "Fix the gutter", bucket: :later, created_at: 6.weeks.ago)
    suggestion = propose(watcher_slug: "stale_task", fingerprint: "stale_task/task:#{task.id}/x",
      action: { "schedule_task" => { "id" => task.id } })

    task.destroy!
    AgentScanJob.perform_now(@user)

    assert_predicate suggestion.reload, :resolved?, "there is nothing left to rescue"
  end

  test "a stale-task nudge survives while the task is still stranded" do
    task = @user.tasks.create!(title: "Fix the gutter", bucket: :later, created_at: 6.weeks.ago)
    suggestion = propose(watcher_slug: "stale_task", fingerprint: "stale_task/task:#{task.id}/x",
      action: { "schedule_task" => { "id" => task.id } })

    AgentScanJob.perform_now(@user)

    assert_predicate suggestion.reload, :pending?
  end

  test "a stay-in-touch nudge retires once contact is logged" do
    person = @user.people.create!(name: "Mom", keep_in_touch: true, last_contacted_on: 200.days.ago.to_date)
    suggestion = propose(watcher_slug: "stay_in_touch", fingerprint: "stay_in_touch/person:#{person.id}/q",
      action: {})

    person.update!(last_contacted_on: Date.current)
    AgentScanJob.perform_now(@user)

    assert_predicate suggestion.reload, :resolved?
  end

  test "a goal-stall nudge retires when the goal is paused" do
    # D-goal-pause: a goal parked on purpose is not a stalled one, and
    # nudging about it is the shame that decision exists to defuse.
    goal = @user.goals.create!(title: "Learn Portuguese", created_at: 8.weeks.ago)
    goal.tasks.create!(user: @user, title: "Find a tutor")
    suggestion = propose(watcher_slug: "goal_stall", fingerprint: "goal_stall/goal:#{goal.id}/x", action: {})

    goal.update!(status: :paused)
    AgentScanJob.perform_now(@user)

    assert_predicate suggestion.reload, :resolved?
  end

  test "retiring frees a capped watcher's slot in the same scan" do
    # stale_task allows three live nudges; the retire pass runs before the
    # scan so a handled one makes room for the next oldest task.
    Watcher::StaleTask::LIMIT.times do |n|
      task = @user.tasks.create!(title: "Old #{n}", bucket: :later, created_at: 6.weeks.ago)
      propose(watcher_slug: "stale_task", fingerprint: "stale_task/task:#{task.id}/x",
        action: { "schedule_task" => { "id" => task.id } })
      task.update!(due_on: Date.current) if n.zero?
    end
    waiting = @user.tasks.create!(title: "Never dated", bucket: :later, created_at: 8.weeks.ago)

    AgentScanJob.perform_now(@user)

    rescued = @user.suggestions.actionable.where(watcher_slug: "stale_task")
      .any? { |suggestion| suggestion.action.dig("schedule_task", "id") == waiting.id }
    assert rescued, "the freed slot went to the next oldest stranded task"
  end

  # Standing in for any watcher whose retire check has a bug in it.
  class ExplodingWatcher < Watcher::Base
    def self.slug = "exploding"
    def scan = nil
    def resolved?(suggestion) = raise("retire bug")
  end

  test "a watcher whose resolved? raises costs neither the scan nor the other watchers" do
    suggestion = propose(watcher_slug: "exploding", fingerprint: "exploding/whatever")

    with_watchers(ExplodingWatcher, Watcher.find!("checkup_cadence")) do
      assert_nothing_raised { AgentScanJob.perform_now(@user) }
    end

    assert_predicate suggestion.reload, :pending?, "a failed check never retires anything"
    recorded = AppError.where(error_class: "RuntimeError").sole
    assert_equal({ "watcher" => ExplodingWatcher.name, "retire" => true }, recorded.context)
    assert @user.suggestions.where(watcher_slug: "checkup_cadence").exists?, "the other watchers still ran"
  end

  test "watchers that never retire are skipped without a query" do
    assert_not Watcher::OnThisDay.retires?
    assert Watcher::StaleTask.retires?
  end

  private
    def with_watchers(*watchers)
      original = Watcher.method(:all)
      Watcher.define_singleton_method(:all) { watchers }
      yield
    ensure
      Watcher.define_singleton_method(:all, original)
    end

    # `on_this_day` never answers `resolved?`, so the expiry tests exercise
    # the watcher-free rule without a watcher's own check confusing matters.
    def propose(watcher_slug: "on_this_day", fingerprint: nil, action: {}, sections: [])
      suggestion = @user.suggestions.create!(
        watcher_slug: watcher_slug,
        fingerprint: fingerprint || "#{watcher_slug}/#{SecureRandom.hex(4)}",
        title: "Something to look at", action: action
      )
      suggestion.sections = sections
      suggestion
    end
end
