require "test_helper"

# D-people-circles: one card per collection of people, the circle first —
# and the circle stays a per-user flag rather than becoming a shared lens.
class People::CirclesTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @people = sections(:people)
  end

  test "the circle is the first card, and it is not a section" do
    @user.people.create!(name: "Sam", keep_in_touch: true)

    card = People::Circles.for(@user, @people).first

    assert card.circle?
    assert_nil card.section
    assert_equal "Your circle", card.name
    assert card.private, "the circle is the owner's intent — the card has to say so"
    assert_equal [ "Sam" ], card.members.map(&:name)
  end

  test "every group gets a card with its members" do
    group = ::People::Group.find_or_create!("Book club")
    member = @user.people.create!(name: "Rosa")
    member.sections << group
    @user.people.create!(name: "Not a member")

    card = People::Circles.for(@user, @people).last

    assert_equal "Book club", card.name
    assert_not card.private, "a group is household-shared taxonomy"
    assert_equal [ "Rosa" ], card.members.map(&:name)
    assert_equal 1, card.member_count
  end

  test "a group card counts everyone visible, not only the viewer's own contacts" do
    group = ::People::Group.find_or_create!("Church")
    theirs = users(:two).people.create!(name: "Spouse's friend")
    theirs.sections << group
    AccessGrant.create!(grantor: users(:two), grantee: @user, subject: theirs)

    card = People::Circles.for(@user, @people).last
    assert_equal [ "Spouse's friend" ], card.members.map(&:name)
  end

  test "a group card hides members the viewer cannot see" do
    group = ::People::Group.find_or_create!("Church")
    theirs = users(:two).people.create!(name: "Unshared")
    theirs.sections << group

    card = People::Circles.for(@user, @people).last
    assert_empty card.members
    assert_equal "No one here yet", card.signal
  end

  test "the circle signal names drift with the watcher's own window" do
    @user.people.create!(name: "Fresh", keep_in_touch: true, last_contacted_on: Date.current)
    @user.people.create!(name: "Drifted", keep_in_touch: true,
      last_contacted_on: (Watcher::StayInTouch::QUIET_AFTER + 1.day).ago.to_date)

    assert_equal "2 people · 1 you haven't talked to in a while",
      People::Circles.for(@user, @people).first.signal
  end

  test "a never-logged person is not called drifted (Q8: no signal, no claim)" do
    @user.people.create!(name: "Flagged", keep_in_touch: true)

    assert_equal "1 person · 1 with no contact logged yet",
      People::Circles.for(@user, @people).first.signal
  end

  test "an empty circle invites rather than reporting zero" do
    assert_equal "No one yet — pick the relationships you're tending",
      People::Circles.for(@user, @people).first.signal
  end

  test "a group's signal is what's in flight when nothing is dated" do
    group = ::People::Group.find_or_create!("Book club")
    @user.people.create!(name: "Rosa").sections << group
    @user.tasks.create!(title: "Bring snacks").sections << group

    assert_equal "1 person · 1 open task", People::Circles.for(@user, @people).last.signal
  end

  test "a birthday inside the group beats what's in flight" do
    group = ::People::Group.find_or_create!("Book club")
    @user.people.create!(name: "Rosa", birthday: 10.days.from_now.to_date - 30.years).sections << group
    @user.tasks.create!(title: "Bring snacks").sections << group

    assert_match "Rosa's birthday", People::Circles.for(@user, @people).last.signal
  end

  test "the next event beats everything else" do
    group = ::People::Group.find_or_create!("Book club")
    @user.people.create!(name: "Rosa", birthday: 10.days.from_now.to_date - 30.years).sections << group
    @user.events.create!(title: "Potluck", starts_at: 3.days.from_now).sections << group

    assert_match "Potluck", People::Circles.for(@user, @people).last.signal
  end

  test "a distant birthday is not the signal" do
    group = ::People::Group.find_or_create!("Book club")
    @user.people.create!(name: "Rosa", birthday: 6.months.from_now.to_date - 30.years).sections << group

    assert_equal "1 person · nothing planned yet", People::Circles.for(@user, @people).last.signal
  end

  test "a quiet group says so honestly" do
    group = ::People::Group.find_or_create!("Book club")
    @user.people.create!(name: "Rosa").sections << group

    assert_equal "1 person · nothing planned yet", People::Circles.for(@user, @people).last.signal
  end

  test "members load in one query however many groups there are" do
    3.times do |i|
      group = ::People::Group.find_or_create!("Group #{i}")
      2.times { |j| @user.people.create!(name: "Member #{i}#{j}").sections << group }
    end

    cards = nil
    member_queries = count_queries(/FROM "people"/) { cards = People::Circles.for(@user, @people) }

    assert_equal 6, cards.sum(&:member_count)
    assert_equal 2, member_queries,
      "one query for the circle and one for every group's members — this grid degrades first after a CardDAV sync"
  end

  private
    def count_queries(pattern)
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        count += 1 if payload[:sql]&.match?(pattern) && !payload[:name].to_s.include?("SCHEMA")
      end
      yield
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
end
