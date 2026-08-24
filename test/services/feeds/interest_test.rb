require "test_helper"

class Feeds::InterestTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @feed = @user.feeds.create!(url: "https://example.com/feed.xml")
    @woodworking = Hobbies::Lens.find_or_create!("Woodworking")
  end

  test "the hobby's own words score above an unrelated headline" do
    interest = Feeds::Interest.for(@user)

    assert_operator interest.score("A woodworking bench for small shops"), :>,
      interest.score("Quarterly earnings beat expectations")
  end

  test "what the user keeps under a hobby becomes vocabulary" do
    @user.notes.create!(title: "Dovetail jig settings", body: "…").tap { |note| note.sections = [ @woodworking ] }
    interest = Feeds::Interest.for(@user)

    assert_operator interest.score("A better dovetail jig"), :>, 0.0
  end

  test "a downvote pushes the words it was made of down" do
    before = Feeds::Interest.for(@user).score("Another AI gadget roundup")
    @feed.feed_items.create!(guid: "1", title: "Another AI gadget roundup", vote: FeedItem::DOWN)

    assert_operator Feeds::Interest.for(@user).score("Another AI gadget roundup"), :<, before
  end

  test "an upvote lifts them" do
    before = Feeds::Interest.for(@user).score("Hand-cut joinery, start to finish")
    @feed.feed_items.create!(guid: "1", title: "Hand-cut joinery, start to finish", vote: FeedItem::UP)

    assert_operator Feeds::Interest.for(@user).score("Hand-cut joinery, start to finish"), :>, before
  end

  test "an item from a filed feed is about that hobby whatever its headline says" do
    interest = Feeds::Interest.for(@user)

    assert_operator interest.score("Episode 412", sections: [ @woodworking ]), :>,
      interest.score("Episode 412")
  end

  test "scores stay inside -1..1 however many words match" do
    long = ([ "woodworking dovetail jig bench chisel" ] * 20).join(" ")

    assert_operator Feeds::Interest.for(@user).score(long), :<=, 1.0
  end

  test "another household member's votes never move this user's ranking" do
    other = users(:two)
    other_feed = other.feeds.create!(url: "https://example.com/other.xml")
    other_feed.feed_items.create!(guid: "1", title: "Sourdough starter troubleshooting", vote: FeedItem::UP)

    assert_equal 0.0, Feeds::Interest.for(@user).score("Sourdough starter troubleshooting")
  end

  test "the reasons behind a lift are the user's own nouns" do
    interest = Feeds::Interest.for(@user)

    assert_includes interest.reasons("A woodworking bench", sections: [ @woodworking ]), "Woodworking"
  end

  test "stop words alone never lift anything" do
    assert_equal 0.0, Feeds::Interest.for(@user).score("What you should have from the one that was here")
  end
end
