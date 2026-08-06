require "test_helper"

# D21 end-to-end: cross-user coordination through visible_to and nothing
# else — the watcher structurally cannot reference unshared items.
class SameDaySyncWatcherTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
    @bob = users(:two)
    @day = 4.days.from_now.to_date
    @alice.events.create!(title: "Dentist", starts_at: @day.in_time_zone.change(hour: 9), all_day: false)
  end

  test "shared same-day timed events produce a coordination heads-up" do
    bobs = @bob.events.create!(title: "Physical", starts_at: @day.in_time_zone.change(hour: 11), all_day: false)
    AccessGrant.create!(grantor: @bob, grantee: @alice, subject: bobs)

    Watcher::SameDaySync.new(@alice).scan

    suggestion = @alice.suggestions.sole
    assert_match "You and Bob Smith are both out", suggestion.title
    assert_match "Physical", suggestion.body
    assert suggestion.heads_up?
    assert_equal (@day - 1).iso8601, suggestion.action.dig("task", "due_on")
  end

  test "unshared events never surface — the privacy model is the query" do
    @bob.events.create!(title: "Private appointment", starts_at: @day.in_time_zone.change(hour: 11), all_day: false)

    Watcher::SameDaySync.new(@alice).scan

    assert_empty @alice.suggestions
  end

  test "all-day events and non-overlapping days stay quiet" do
    shared_all_day = @bob.events.create!(title: "Bob's conference", starts_at: @day.in_time_zone, all_day: true)
    AccessGrant.create!(grantor: @bob, grantee: @alice, subject: shared_all_day)
    other_day = @bob.events.create!(title: "Different day", starts_at: (@day + 3).in_time_zone.change(hour: 10), all_day: false)
    AccessGrant.create!(grantor: @bob, grantee: @alice, subject: other_day)

    Watcher::SameDaySync.new(@alice).scan

    assert_empty @alice.suggestions
  end
end
