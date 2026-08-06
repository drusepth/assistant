require "test_helper"

# The M3.2 watcher slate. Deterministic scans only — every test is pure
# data in, suggestion (or silence) out.
class WatchersTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "stay-in-touch nudges about a quiet person and prefills the Reconnect tool" do
    mom = @user.people.create!(name: "Mom", last_contacted_on: 4.months.ago.to_date)
    @user.people.create!(name: "Recent friend", last_contacted_on: 2.weeks.ago.to_date)
    @user.people.create!(name: "Never logged")

    Watcher::StayInTouch.new(@user).scan

    suggestion = @user.suggestions.sole
    assert_equal "Reach out to Mom", suggestion.title
    assert_equal({ "tool" => { "slug" => "reconnect", "inputs" => { "person_id" => mom.id.to_s } } }, suggestion.action)
    assert_includes suggestion.sections, sections(:people)
  end

  test "stay-in-touch says nothing about people with no logged contact" do
    @user.people.create!(name: "Never logged")

    Watcher::StayInTouch.new(@user).scan

    assert_empty @user.suggestions, "no signal, no nudge — the app doesn't guess"
  end

  test "renewal radar flags a lease-end event with lead time" do
    event = @user.events.create!(title: "Lease renewal deadline", starts_at: 5.weeks.from_now, all_day: true)
    event.sections << sections(:renting)
    @user.events.create!(title: "Lease renewal far away", starts_at: 5.months.from_now, all_day: true)
    @user.events.create!(title: "Dentist", starts_at: 2.weeks.from_now, all_day: true)

    Watcher::RenewalRadar.new(@user).scan

    suggestion = @user.suggestions.sole
    assert_match(/Lease renewal deadline/, suggestion.title)
    assert suggestion.heads_up?
    assert_equal (5.weeks.from_now.to_date - 14).iso8601, suggestion.action.dig("task", "due_on"),
      "the follow-up task lands two weeks ahead of the date"
    assert_equal [ sections(:renting) ], suggestion.sections.to_a, "filed where the event is filed"
  end

  test "goal stall flags an abandoned goal and files under its sections" do
    goal = travel_to(3.weeks.ago) do
      goal = @user.goals.create!(title: "Get a job", broken_down_at: Time.current)
      goal.sections << sections(:career)
      @user.tasks.create!(goal: goal, title: "Update resume", completed_at: Time.current)
      goal
    end

    Watcher::GoalStall.new(@user).scan

    suggestion = @user.suggestions.sole
    assert_match(/looks stalled/, suggestion.title)
    assert_equal [ sections(:career) ], suggestion.sections.to_a
    assert_equal Date.current.iso8601, suggestion.action.dig("task", "due_on")
  end

  test "goal stall stays quiet when a step is done recently or scheduled soon" do
    active = @user.goals.create!(title: "Active goal", created_at: 3.weeks.ago, broken_down_at: Time.current)
    @user.tasks.create!(goal: active, title: "Done yesterday", completed_at: 1.day.ago)

    scheduled = @user.goals.create!(title: "Scheduled goal", created_at: 3.weeks.ago, broken_down_at: Time.current)
    @user.tasks.create!(goal: scheduled, title: "Due soon", due_on: 3.days.from_now.to_date)

    Watcher::GoalStall.new(@user).scan

    assert_empty @user.suggestions
  end
end
