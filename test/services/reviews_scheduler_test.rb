require "test_helper"

# The FSRS battery (D-review-scheduler): properties over golden numbers —
# the defaults may be retuned, but these shapes are what spaced repetition
# *means*, and a change that breaks one is a bug wherever the weights land.
class ReviewsSchedulerTest < ActiveSupport::TestCase
  setup do
    @item = users(:one).review_items.create!(topic: topics(:fractions_compare), prompt: "Which is bigger, 2/3 or 3/5?")
  end

  test "a first Good schedules days out; a first Again stays sub-hour" do
    Reviews::Scheduler.grade!(@item, :good)

    assert @item.review?
    assert_operator @item.due_at, :>, 1.day.from_now - 1.minute
    assert_equal 1, @item.reps

    fresh = users(:one).review_items.create!(topic: topics(:fractions_compare), prompt: "p2")
    Reviews::Scheduler.grade!(fresh, :again)
    assert fresh.learning?
    assert_operator fresh.due_at, :<, 1.hour.from_now
    assert_equal 0, fresh.lapses, "a first stumble is learning, not a lapse"
  end

  test "intervals expand under repeated Good — the spacing effect is the point" do
    now = Time.current
    intervals = []
    4.times do
      Reviews::Scheduler.grade!(@item, :good, now: now)
      interval = @item.due_at - now
      intervals << interval
      now = @item.due_at
    end

    assert_equal intervals.sort, intervals, "each interval outgrows the last"
    assert_operator intervals.last, :>, intervals.first * 2
  end

  test "easy outruns good outruns hard" do
    now = Time.current
    dues = %w[ hard good easy ].map do |rating|
      item = users(:one).review_items.create!(topic: topics(:fractions_compare), prompt: "p-#{rating}")
      Reviews::Scheduler.grade!(item, :good, now: now - 10.days)
      Reviews::Scheduler.grade!(item, rating, now: now)
      item.due_at
    end

    assert_operator dues[0], :<, dues[1]
    assert_operator dues[1], :<, dues[2]
  end

  test "a lapse shrinks stability, counts, and comes back in minutes" do
    now = Time.current
    Reviews::Scheduler.grade!(@item, :good, now: now)
    stable = @item.stability

    Reviews::Scheduler.grade!(@item, :again, now: @item.due_at)

    assert @item.relearning?
    assert_operator @item.stability, :<, stable
    assert_equal 1, @item.lapses
    assert_operator @item.due_at, :<, @item.last_reviewed_at + 1.hour

    Reviews::Scheduler.grade!(@item, :good, now: @item.due_at)
    assert @item.review?, "a clean answer graduates relearning"
  end

  test "retrievability decays with time and never rises on its own" do
    Reviews::Scheduler.grade!(@item, :good)

    soon = Reviews::Scheduler.retrievability(@item, now: @item.last_reviewed_at + 1.day)
    late = Reviews::Scheduler.retrievability(@item, now: @item.last_reviewed_at + 60.days)

    assert_operator soon, :>, late
    assert_operator soon, :<=, 1.0
    assert_operator late, :>, 0.0
  end

  test "the quartet preview matches what grading would actually do" do
    Reviews::Scheduler.grade!(@item, :good, now: 10.days.ago)
    preview = Reviews::Scheduler.preview(@item)

    assert_equal "10 min", preview["again"]
    Reviews::Scheduler.grade!(@item, :good)
    assert_equal preview["good"], Reviews::Scheduler.interval_label(@item.due_at, @item.last_reviewed_at)
  end
end
