require "test_helper"

# The reader's doorway on the Hobbies page (D-feed-reader). Its own file
# rather than an edit to sections_controller_test: a section feature adds
# files, it doesn't touch the shared ones (D37).
class HobbiesReaderPanelTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "with no feeds the panel invites a first source in place" do
    get section_path("hobbies")

    assert_response :success
    assert_match "From your feeds", response.body
    assert_match "reddit.com/r/woodworking", response.body
  end

  test "with feeds the panel leads with what the ranking would lead with" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    feed = users(:one).feeds.create!(url: "https://example.com/wood.xml", label: "Wood", sections: [ lens ])
    feed.feed_items.create!(guid: "1", title: "A woodworking bench", published_at: 2.hours.ago, relevance: 0.9)
    feed.feed_items.create!(guid: "2", title: "Old and read", published_at: 3.days.ago, read_at: Time.current)

    get section_path("hobbies")

    assert_match "A woodworking bench", response.body
    assert_no_match "Old and read", response.body
    assert_match(/1 unread/, response.body)
  end

  test "another member's feeds are not on your Hobbies page" do
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml")
    theirs.feed_items.create!(guid: "1", title: "Bob's private reading")

    get section_path("hobbies")

    assert_no_match "Bob's private reading", response.body
  end
end
