require "test_helper"

# The reader inside the Hobbies hub (D-hobby-feeds): one river per hobby
# card, the catch-all lens at the end, and each hobby's own page carrying
# the same river at depth. Its own file rather than an edit to
# sections_controller_test: a section feature adds files, it doesn't touch
# the shared ones (D37).
class HobbiesReaderPanelTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "before any hobby exists the page still leads with the capture question" do
    get section_path("hobbies")

    assert_response :success
    assert_match(/What do you do for fun/i, response.body)
  end

  test "a hobby with no feeds invites a first source in its own card" do
    Hobbies::Lens.find_or_create!("Woodworking")

    get section_path("hobbies")

    assert_response :success
    assert_match "Woodworking", response.body
    assert_match(/Follow the sites, blogs and channels behind this hobby/, response.body)
  end

  test "a hobby's card carries its newest unread and a link into that hobby's river" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    feed = users(:one).feeds.create!(url: "https://example.com/wood.xml", label: "Wood", sections: [ lens ])
    feed.feed_items.create!(guid: "1", title: "A woodworking bench", published_at: 2.hours.ago)
    feed.feed_items.create!(guid: "2", title: "Old and read", published_at: 3.days.ago, read_at: Time.current)

    get section_path("hobbies")

    assert_match "A woodworking bench", response.body
    assert_no_match "Old and read", response.body
    assert_match CGI.escapeHTML(reader_path(hobby: lens.slug)), response.body
  end

  test "each hobby's stories stay on its own card" do
    wood = Hobbies::Lens.find_or_create!("Woodworking")
    baking = Hobbies::Lens.find_or_create!("Baking")
    users(:one).feeds.create!(url: "https://example.com/wood.xml", sections: [ wood ])
      .feed_items.create!(guid: "1", title: "Bench hooks")
    users(:one).feeds.create!(url: "https://example.com/bake.xml", sections: [ baking ])
      .feed_items.create!(guid: "2", title: "Sourdough starters")

    get section_path("hobbies")

    cards = Nokogiri::HTML(response.body).css("[data-hobby-card]").index_by { |node| node["data-hobby-card"] }
    wood_card = cards.fetch(wood.slug).text
    baking_card = cards.fetch(baking.slug).text
    assert_includes wood_card, "Bench hooks"
    assert_not_includes wood_card, "Sourdough starters"
    assert_includes baking_card, "Sourdough starters"
  end

  test "a feed no hobby claimed shows up under Other Interests, last in the grid" do
    Hobbies::Lens.find_or_create!("Woodworking")
    feed = users(:one).feeds.create!(url: "https://example.com/news.xml", label: "World news")
    feed.sections = [ Hobbies::OtherInterests.find_or_create! ]
    feed.feed_items.create!(guid: "1", title: "Something happened somewhere")

    get section_path("hobbies")

    assert_match "Other Interests", response.body
    assert_match "Something happened somewhere", response.body

    slugs = Nokogiri::HTML(response.body).css("[data-hobby-card]").map { |node| node["data-hobby-card"] }
    assert_equal Hobbies::OtherInterests::SLUG, slugs.last,
      "the catch-all is the floor of the grid, not a hobby under O"
  end

  test "the hub links out to the everything-view and to the feed list" do
    Hobbies::Lens.find_or_create!("Woodworking")

    get section_path("hobbies")

    assert_match CGI.escapeHTML(reader_path), response.body
    assert_match CGI.escapeHTML(feeds_path), response.body
  end

  test "another member's feeds are not on your Hobbies page" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml", sections: [ lens ])
    theirs.feed_items.create!(guid: "1", title: "Bob's private reading")

    get section_path("hobbies")

    assert_no_match "Bob's private reading", response.body
  end

  # The parent-lens panel fallback: a hobby page is a section page for a row
  # the user made, so no class can be named after its slug.
  test "a hobby's own page carries that hobby's river" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    other = Hobbies::Lens.find_or_create!("Baking")
    users(:one).feeds.create!(url: "https://example.com/wood.xml", sections: [ lens ])
      .feed_items.create!(guid: "1", title: "Bench hooks")
    users(:one).feeds.create!(url: "https://example.com/bake.xml", sections: [ other ])
      .feed_items.create!(guid: "2", title: "Sourdough starters")

    get section_path(lens.slug)

    assert_response :success
    assert_match "Bench hooks", response.body
    assert_no_match "Sourdough starters", response.body
    assert_match CGI.escapeHTML(reader_path(hobby: lens.slug)), response.body
  end

  test "a hobby page with no feeds asks for one, pre-tagged with that hobby" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")

    get section_path(lens.slug)

    assert_response :success
    assert_select "form[action=?] input[name='feed[section_ids][]'][value=?]", feeds_path, lens.id.to_s
  end

  test "the catch-all lens is not removable from its own page" do
    lens = Hobbies::OtherInterests.find_or_create!

    get section_path(lens.slug)

    assert_response :success
    assert_no_match(/Remove this hobby/, response.body)

    delete hobby_path(lens)

    assert_response :not_found
    assert Hobbies::OtherInterests.find, "the invariant is protected at the controller layer"
  end
end
