require "test_helper"

# The dashboard hub board: one card per enabled life area, wide when the
# area has work in it and narrow when it's quiet.
class Dashboard::BoardTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @hobbies = Section.find_by(slug: "hobbies")
    @money = Section.find_by(slug: "money")
    @subscriptions = @money.children.first
  end

  test "cards every enabled top-level section and no subsections" do
    cards = Dashboard::Board.new(@user).cards

    assert_equal @user.enabled_sections.reject(&:parent_id).map(&:name).sort,
      cards.map { |card| card.section.name }.sort
    assert_empty cards.select { |card| card.section.parent_id }
  end

  test "an area with nothing in it reads as quiet and clear" do
    card = card_for(@hobbies)

    assert card.quiet?
    assert_not card.wide?
    assert_equal "Clear", card.status
    assert_equal "Nothing due", card.headline
  end

  test "an area with open work goes wide and leads with what is overdue" do
    tag(create_task("Overdue thing", 2.days.ago), @hobbies)
    tag(create_task("Due today", Date.current), @hobbies)
    tag(create_task("Later", 3.days.from_now), @hobbies)

    card = card_for(@hobbies)

    assert card.wide?
    assert_equal 3, card.open_count
    assert_equal 1, card.overdue_count
    assert_equal "3 open · 1 overdue", card.status
    assert_equal [ "Overdue thing", "Due today", "Later" ], card.tasks.map(&:title)
  end

  test "rows stop at ROWS and the remainder is left to the count" do
    (Dashboard::Board::ROWS + 2).times { |i| tag(create_task("Task #{i}", Date.current), @hobbies) }

    card = card_for(@hobbies)

    assert_equal Dashboard::Board::ROWS, card.tasks.size
    assert_equal Dashboard::Board::ROWS + 2, card.open_count
  end

  test "a task tagged only to a subsection rolls up onto its parent's card" do
    tag(create_task("Subscription review", Date.current), @subscriptions)

    assert_equal [ "Subscription review" ], card_for(@money).tasks.map(&:title)
  end

  test "a task tagged to both a parent and its child counts once" do
    task = create_task("Dual tagged", Date.current)
    tag(task, @money)
    tag(task, @subscriptions)

    card = card_for(@money)

    assert_equal 1, card.open_count
    assert_equal [ "Dual tagged" ], card.tasks.map(&:title)
  end

  test "completed work leaves the board" do
    tag(create_task("Done", Date.current), @hobbies).update!(completed_at: Time.current)

    assert card_for(@hobbies).quiet?
  end

  test "another member's private work stays off the board" do
    task = users(:two).tasks.create!(title: "Not yours", due_on: Date.current)
    task.sections << @hobbies

    assert card_for(@hobbies).quiet?
  end

  test "busy areas sort ahead of quiet ones" do
    tag(create_task("Something", Date.current), @money)

    names = Dashboard::Board.new(@user).sorted_cards.map { |card| card.section.name }

    assert_equal "Money", names.first
  end

  private
    def card_for(section)
      Dashboard::Board.new(@user).cards.find { |card| card.section == section }
    end

    def create_task(title, due_on)
      @user.tasks.create!(title: title, due_on: due_on)
    end

    def tag(task, section)
      task.sections << section
      task
    end
end
