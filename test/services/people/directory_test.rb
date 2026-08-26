require "test_helper"

# D-address-book-directory: the roster's query, its A–Z shape, and the
# counts on its filter row — the parts that decide whether the page still
# works the morning after a CardDAV import.
class People::DirectoryTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "people come back A–Z regardless of case" do
    @user.people.create!(name: "abby Nguyen")
    @user.people.create!(name: "Bo Chen")
    @user.people.create!(name: "Zoe Park")

    assert_equal [ "abby Nguyen", "Bo Chen", "Zoe Park" ],
      People::Directory.new(@user).people.map(&:name),
      "SQLite's binary collation would file every lowercase name after Zoe"
  end

  test "letters hold only the buckets that have somebody, and names that start with neither get one of their own" do
    @user.people.create!(name: "Abby")
    @user.people.create!(name: "이준")

    letters = People::Directory.new(@user).letters

    assert_equal [ "A", "#" ], letters.map(&:key)
    assert_equal [ "Abby" ], letters.first.people.map(&:name)
    assert_equal "letter-a", letters.first.anchor
    assert_equal "letter-other", letters.last.anchor
  end

  test "search matches every field the row can show" do
    @user.people.create!(name: "Rosa Alvarez", email: "rosa@example.com")
    @user.people.create!(name: "Bo Chen", relationship: "Cardiologist")
    @user.people.create!(name: "Dee Ellis", notes: "Met at the co-op")

    assert_equal [ "Rosa Alvarez" ], names_for(query: "example.com")
    assert_equal [ "Bo Chen" ], names_for(query: "cardio")
    assert_equal [ "Dee Ellis" ], names_for(query: "co-op")
  end

  test "a LIKE wildcard in the query is a character, not a wildcard" do
    @user.people.create!(name: "Rosa Alvarez")

    assert_empty names_for(query: "%"),
      "an unescaped % would silently match the whole address book"
  end

  test "circle mode never reaches past your own contacts" do
    theirs = users(:two).people.create!(name: "Shared Sal", keep_in_touch: true)
    AccessGrant.create!(grantor: users(:two), grantee: @user, subject: theirs)
    @user.people.create!(name: "Circle Sam", keep_in_touch: true)

    assert_equal [ "Circle Sam" ], People::Directory.new(@user, circle: true).people.map(&:name),
      "you don't tend your spouse's circle (D-people-dashboard)"
  end

  test "group chips carry counts, skip empty groups, and count only what the viewer can see" do
    club = ::People::Group.find_or_create!("Book club")
    ::People::Group.find_or_create!("Ghost town")
    @user.people.create!(name: "Rosa").sections << club
    users(:two).people.create!(name: "Invisible Ivan").sections << club

    chips = People::Directory.new(@user).group_chips

    assert_equal [ [ "Book club", 1 ] ], chips.map { |section, count| [ section.name, count ] }
  end

  test "every chip's count is one query, however many groups there are" do
    3.times do |index|
      group = ::People::Group.find_or_create!("Group #{index}")
      @user.people.create!(name: "Member #{index}").sections << group
    end
    directory = People::Directory.new(@user)

    # This is the row that silently degrades the day somebody makes twenty
    # groups, so the batching is the assertion, not the numbers.
    # Three flat: the People lens, its children, and one grouped count over
    # all of them — the third is the one that would otherwise be per-chip.
    assert_queries_count 3 do
      assert_equal 3, directory.group_chips.size
    end
  end

  test "an unknown group slug filters nothing" do
    @user.people.create!(name: "Rosa")
    directory = People::Directory.new(@user, group_slug: "deleted-last-tuesday")

    assert_nil directory.group
    assert_equal [ "Rosa" ], directory.people.map(&:name)
  end

  test "the count phrase's two numbers come off the filtered set and the whole roster" do
    @user.people.create!(name: "Rosa Alvarez")
    @user.people.create!(name: "Bo Chen")
    directory = People::Directory.new(@user, query: "rosa")

    assert_equal 1, directory.total
    assert_equal 2, directory.roster_size
  end

  private
    def names_for(**options) = People::Directory.new(@user, **options).people.map(&:name)
end
