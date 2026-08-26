require "test_helper"

# The stocked shelf (D-hobby-feeds §7.1). The rules it has to keep are the
# reader's first promise: offered, never subscribed; static and offline;
# publisher-run sources only.
class Feeds::StartersTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    Feeds::Starters.reload!
  end

  test "the shipped list is real, grouped, and points at publishers rather than aggregators" do
    entries = Feeds::Starters.entries

    assert entries.many?
    assert entries.all? { |entry| entry.url.start_with?("https://") }, "no plaintext http on a shelf we ship"
    assert entries.all? { |entry| entry.title.present? && entry.folder.present? }
    assert_equal entries.map(&:url).uniq, entries.map(&:url)

    hosts = entries.map { |entry| URI.parse(entry.url).host }
    assert_empty hosts.grep(/feedburner|feedproxy|rss\.app/),
      "a feed living on somebody else's redirector is the failure mode this feature answers"
  end

  test "building the list fetches nothing" do
    assert_not_requested :any, //
    assert Feeds::Starters.groups.any?
    assert_not_requested :any, //
  end

  test "ticking rows follows exactly those, through the ordinary OPML path" do
    picks = Feeds::Starters.entries.first(2).map(&:url)

    result = Feeds::Starters.import(@user, picks)

    assert_equal 2, result.added
    assert_equal picks.sort, @user.feeds.pluck(:url).sort
  end

  test "nothing ticked follows nothing" do
    assert_no_difference "Feed.count" do
      assert_equal 0, Feeds::Starters.import(@user, []).added
    end
  end

  test "a url that is not on the shelf can't be smuggled in through it" do
    assert_no_difference "Feed.count" do
      Feeds::Starters.import(@user, [ "https://example.com/not-on-the-shelf.xml" ])
    end
  end

  # The groups are hobby names, and ticking one is the user saying they are
  # interested in it — so unlike an exported file's folders, these may become
  # hobbies. The user can still say no.
  test "a ticked group becomes a hobby, unless the user unticks that" do
    entry = Feeds::Starters.entries.first

    Feeds::Starters.import(@user, [ entry.url ])
    lens = Hobbies::Lens.named(entry.folder)
    assert lens, "the group the user ticked is the hobby"
    assert_equal [ lens ], @user.feeds.sole.sections.to_a

    @user.feeds.destroy_all
    lens.destroy!
    Feeds::Starters.import(@user, [ entry.url ], create_lenses: false)
    assert_nil Hobbies::Lens.named(entry.folder)
    assert_equal [ Hobbies::OtherInterests.find ], @user.feeds.sole.sections.to_a
  end

  test "a feed already followed is offered no more" do
    entry = Feeds::Starters.entries.first
    @user.feeds.create!(url: entry.url)

    assert_not_includes Feeds::Starters.unfollowed_for(@user).map(&:url), entry.url
    assert Feeds::Starters.unfollowed_for(@user).any?
  end
end
