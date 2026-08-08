require "test_helper"

# Per-lens engagement signal for the Hobbies grid: next planned event and
# in-flight counts, batched, and always through visible_to (D9).
class Hobbies::LensSummaryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @guitar = Hobbies::Lens.find_or_create!("Guitar")
    @chess = Hobbies::Lens.find_or_create!("Chess")
  end

  test "returns the soonest upcoming event and open counts per lens" do
    later = @user.events.create!(title: "Recital", starts_at: 2.weeks.from_now)
    later.sections << @guitar
    sooner = @user.events.create!(title: "Lesson", starts_at: 2.days.from_now)
    sooner.sections << @guitar
    past = @user.events.create!(title: "Old jam", starts_at: 1.week.ago)
    past.sections << @guitar

    open_task = @user.tasks.create!(title: "Restring")
    open_task.sections << @guitar
    done_task = @user.tasks.create!(title: "Buy picks", completed_at: Time.current)
    done_task.sections << @guitar
    goal = @user.goals.create!(title: "Learn the solo")
    goal.sections << @guitar

    guitar, chess = Hobbies::LensSummary.for(@user, [ @guitar, @chess ])

    assert_equal "Lesson", guitar.next_event.title
    assert_equal 1, guitar.open_tasks_count
    assert_equal 1, guitar.active_goals_count
    assert_not guitar.quiet?

    assert_nil chess.next_event
    assert_equal 0, chess.open_tasks_count
    assert_equal 0, chess.active_goals_count
    assert chess.quiet?
  end

  test "only counts items visible to the viewer" do
    other_task = users(:two).tasks.create!(title: "Bob's practice")
    other_task.sections << @guitar
    other_event = users(:two).events.create!(title: "Bob's gig", starts_at: 1.day.from_now)
    other_event.sections << @guitar

    guitar, = Hobbies::LensSummary.for(@user, [ @guitar ])

    assert_nil guitar.next_event
    assert_equal 0, guitar.open_tasks_count
    assert guitar.quiet?
  end

  test "returns nothing for no lenses" do
    assert_equal [], Hobbies::LensSummary.for(@user, [])
  end
end
