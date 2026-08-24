require "test_helper"

# The two date-only surfaces: what a locked diary is allowed to draw, and
# the one that makes years of entries pay off.
class DiaryCalendarTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    keyring = Keyring.initialize_for(@user, "password")
    @session = Diary::Session.new(@user, keyring.unlock("password"))
  end

  def write(on:, body: "Something happened.")
    entry = @user.diary_entries.new(entry_date: on)
    @session.write!(entry, { "body" => body })
    entry
  end

  test "around_day_of_year catches a few days either side, in any year" do
    today = Date.new(2026, 6, 15)

    exact = write(on: Date.new(2024, 6, 15))
    near = write(on: Date.new(2023, 6, 17))
    far = write(on: Date.new(2023, 6, 25))

    found = @user.diary_entries.around_day_of_year(today).to_a

    assert_includes found, exact
    assert_includes found, near, "a few days either side is what people mean by this week last year"
    assert_not_includes found, far
  end

  test "the window spans a year boundary rather than falling in a hole" do
    new_year = Date.new(2026, 1, 1)
    just_before = write(on: Date.new(2022, 12, 30))

    assert_includes @user.diary_entries.around_day_of_year(new_year).to_a, just_before
  end

  test "a leap day window doesn't raise on a common year" do
    assert_nothing_raised do
      @user.diary_entries.around_day_of_year(Date.new(2027, 3, 1)).to_a
    end
  end

  test "the calendar's data is dates only, so it draws the same locked" do
    write(on: Date.current, body: "Unmistakable-calendar-body.")

    locked = Diary::Session.new(@user, nil)
    opened = locked.open_all(@user.diary_entries)

    assert opened.all?(&:lost?), "a locked session must not open anything"
    assert_equal [ Date.current ], @user.diary_entries.pluck(:entry_date).map(&:to_date),
      "and the dates are still there to draw a calendar from"
  end
end
