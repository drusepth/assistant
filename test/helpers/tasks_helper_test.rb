require "test_helper"

# The due label is the one piece of arithmetic the Today page does for you:
# a list of dates makes you subtract before you can triage, so the days
# either side of today speak in days instead.
class TasksHelperTest < ActionView::TestCase
  include TasksHelper
  include ActiveSupport::Testing::TimeHelpers

  setup { travel_to Time.zone.local(2026, 8, 23, 9) }

  test "no due date has nothing to say" do
    assert_nil task_due_label(task(due_on: nil))
  end

  test "today and tomorrow are named, not dated" do
    assert_equal "Due today", task_due_label(task(due_on: Date.current))
    assert_equal "Due tomorrow", task_due_label(task(due_on: Date.tomorrow))
  end

  test "a late task counts the days it is late" do
    assert_equal "1 day late", task_due_label(task(due_on: Date.current - 1))
    assert_equal "15 days late", task_due_label(task(due_on: Date.current - 15))
  end

  test "the rest of this week reads as a weekday" do
    assert_equal "Due Tuesday", task_due_label(task(due_on: Date.current + 2))
    assert_equal "Due Saturday", task_due_label(task(due_on: Date.current + 6))
  end

  test "anything further out keeps the plain date" do
    assert_equal "Due Sep 1", task_due_label(task(due_on: Date.current + 9))
  end

  test "a finished task keeps the plain date — how late it was is no longer news" do
    done = task(due_on: Date.current - 15)
    done.complete!

    assert_equal "Due Aug 8", task_due_label(done)
  end

  private
    def task(attributes) = users(:one).tasks.create!({ title: "A thing" }.merge(attributes))
end
