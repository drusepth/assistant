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

  # Breadth is the shelf's whole job: somebody who has never used a reader
  # should find the thing *they* are into, not a choice between technology
  # and world news. These floors are deliberately well under what ships, so
  # they catch a list being gutted rather than bless an exact size.
  test "the shelf is broad enough to cover the kinds of things people have hobbies about" do
    groups = Feeds::Starters.groups

    assert_operator groups.size, :>=, 30, "a shelf this narrow makes somebody's hobby somebody else's"
    assert_operator Feeds::Starters.entries.size, :>=, 100
    assert_operator Feeds::Starters.entries.size, :<=, Feeds::Opml::MAX_FEEDS,
      "past the import cap the tail of the shelf silently stops being followable"
    assert groups.values.all?(&:any?)
    assert_equal groups.keys.uniq, groups.keys
  end

  # Two rows with the same name in one topic are a copy-paste, and two rows
  # with the same name in a checkbox list are unpickable.
  test "no topic offers the same source twice" do
    Feeds::Starters.groups.each do |folder, entries|
      titles = entries.map(&:title)
      assert_equal titles.uniq, titles, "#{folder} lists a source twice"
    end
  end

  # Explore links a row's name at the publisher's own page, so the shelf has
  # to carry it — a feed URL is where the XML is, not where the reader would
  # go to decide whether they want it (D-feed-explore).
  test "a row knows the site behind it, and what a search matches it on" do
    entry = Feeds::Starters.entries.find { |candidate| candidate.title == "xkcd" }

    assert_equal "https://xkcd.com", entry.site
    assert_equal "xkcd.com", entry.host
    assert_equal "xkcd comics xkcd.com", entry.haystack
    assert Feeds::Starters.entries.count { |candidate| candidate.site.present? } > 100,
      "the file carries htmlUrl on every row; losing it silently would leave Explore linking at XML"
  end

  # The checker (script/check_starter_feeds.rb, run weekly and on any PR that
  # edits the file) is the only thing standing between this list and rot, so
  # the file has to keep pointing at it.
  test "the file says how it is verified" do
    assert_match "check_starter_feeds", Feeds::Starters.reload!.document
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
