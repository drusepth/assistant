require "test_helper"

# The circle scopes and the shared birthday math (docs/PEOPLE.md §2–3):
# next-occurrence dates wrap the year and survive Feb 29, in one place used
# by both the Coming up strip and the birthday-radar watcher.
class PersonTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  # D-contact-photos: the same attachment and guardrails a member's photo
  # gets, on a record that has no login behind it.
  test "a contact photo has to be an image the app can render" do
    person = @user.people.new(name: "Mom")
    person.avatar.attach(io: StringIO.new("not an image"), filename: "notes.txt", content_type: "text/plain")

    assert_not person.valid?
    assert_match(/PNG, JPEG, WEBP, or GIF/, person.errors.full_messages.to_sentence)
  end

  test "initials stand in for a contact with no photo" do
    assert_equal "DR", @user.people.new(name: "dana reed").initials
    assert_not @user.people.new(name: "Dana Reed").avatar_ready?
  end

  test "circle is the flagged subset, stalest first with never-logged last" do
    fresh = @user.people.create!(name: "Fresh", keep_in_touch: true, last_contacted_on: 1.week.ago.to_date)
    stale = @user.people.create!(name: "Stale", keep_in_touch: true, last_contacted_on: 3.months.ago.to_date)
    unlogged = @user.people.create!(name: "Unlogged", keep_in_touch: true)
    @user.people.create!(name: "Not in circle", last_contacted_on: 1.year.ago.to_date)

    assert_equal [ stale, fresh, unlogged ], @user.people.circle.stalest_first.to_a
  end

  test "next_birthday wraps to next year once this year's has passed" do
    passed = @user.people.create!(name: "A", birthday: Date.new(1980, 3, 10))
    ahead = @user.people.create!(name: "B", birthday: Date.new(1980, 9, 10))
    from = Date.new(2026, 6, 1)

    assert_equal Date.new(2027, 3, 10), passed.next_birthday(from: from)
    assert_equal Date.new(2026, 9, 10), ahead.next_birthday(from: from)
  end

  test "a birthday today is today, not next year" do
    person = @user.people.create!(name: "A", birthday: Date.new(1980, 6, 1))

    assert_equal Date.new(2026, 6, 1), person.next_birthday(from: Date.new(2026, 6, 1))
  end

  test "Feb 29 birthdays fall on Feb 28 in common years" do
    person = @user.people.create!(name: "Leap", birthday: Date.new(1996, 2, 29))

    assert_equal Date.new(2026, 2, 28), person.next_birthday(from: Date.new(2026, 1, 1))
    assert_equal Date.new(2028, 2, 29), person.next_birthday(from: Date.new(2027, 3, 1))
  end

  test "birthday_within finds upcoming birthdays across the year boundary, soonest first" do
    december = @user.people.create!(name: "Dec", birthday: Date.new(1980, 12, 28))
    january = @user.people.create!(name: "Jan", birthday: Date.new(1980, 1, 5))
    @user.people.create!(name: "Far", birthday: Date.new(1980, 6, 15))
    @user.people.create!(name: "No birthday")

    assert_equal [ december, january ],
      @user.people.birthday_within(30, from: Date.new(2026, 12, 20))
  end
end
