require "test_helper"

# Per-section engagement signal for the browse grids (hobby cards, seeded
# subsection tiles): next planned event and in-flight counts, batched, and
# always through visible_to (D9).
class Sections::SummaryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @guitar = Hobbies::Lens.find_or_create!("Guitar")
    @chess = Hobbies::Lens.find_or_create!("Chess")
  end

  test "returns the soonest upcoming event and open counts per section" do
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

    guitar, chess = Sections::Summary.for(@user, [ @guitar, @chess ])

    assert_equal "Lesson", guitar.next_event.title
    assert_equal 1, guitar.open_tasks_count
    assert_equal 1, guitar.active_goals_count
    assert_not guitar.quiet?

    assert_nil chess.next_event
    assert_equal 0, chess.open_tasks_count
    assert_equal 0, chess.active_goals_count
    assert chess.quiet?
  end

  test "works over seeded subsections, not just hobby lenses" do
    task = @user.tasks.create!(title: "Review budget")
    task.sections << sections(:budget)

    budget, = Sections::Summary.for(@user, [ sections(:budget) ])

    assert_equal 1, budget.open_tasks_count
    assert_not budget.quiet?
  end

  test "only counts items visible to the viewer" do
    other_task = users(:two).tasks.create!(title: "Bob's practice")
    other_task.sections << @guitar
    other_event = users(:two).events.create!(title: "Bob's gig", starts_at: 1.day.from_now)
    other_event.sections << @guitar

    guitar, = Sections::Summary.for(@user, [ @guitar ])

    assert_nil guitar.next_event
    assert_equal 0, guitar.open_tasks_count
    assert guitar.quiet?
  end

  test "returns nothing for no sections" do
    assert_equal [], Sections::Summary.for(@user, [])
  end
end
