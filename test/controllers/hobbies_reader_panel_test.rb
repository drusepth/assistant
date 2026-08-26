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
    lens = Hobbies::Lens.find_or_create!("Woodworking")

    get section_path("hobbies")

    assert_response :success
    assert_match "Woodworking", response.body
    assert_select "[data-hobby-card=?] summary", lens.slug, text: "+ follow a source"
    assert_select "[data-hobby-card=?] form[action=?] input[name='feed[section_ids][]'][value=?]",
      lens.slug, feeds_path, lens.id.to_s
  end

  # A household names hobbies faster than it follows sources, so the empty
  # case is the common one — and nine open paste forms stacked down the page
  # read as a broken screen rather than an invitation.
  test "many empty hobbies stay closed invitations, and the live ones come first" do
    quiet = 5.times.map { |n| Hobbies::Lens.find_or_create!("Quiet #{n}") }
    live = Hobbies::Lens.find_or_create!("Woodworking")
    users(:one).feeds.create!(url: "https://example.com/wood.xml", sections: [ live ])
      .feed_items.create!(guid: "1", title: "Bench hooks")
    catch_all = Hobbies::OtherInterests.find_or_create!
    users(:one).feeds.create!(url: "https://example.com/news.xml", sections: [ catch_all ])

    get section_path("hobbies")

    page = Nokogiri::HTML(response.body)
    assert_equal quiet.size, page.css("[data-hobby-card] details summary").size,
      "every empty card's form is behind a disclosure"
    assert_empty page.css("[data-hobby-card] input[type=url]").reject { |node| node.ancestors("details").any? },
      "no paste field is open on arrival"

    slugs = page.css("[data-hobby-card]").map { |node| node["data-hobby-card"] }
    assert_equal live.slug, slugs.first, "the card with something in it leads"
    assert_equal catch_all.slug, slugs.last
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

  # docs/READER.md's rule: opening an article marks it read. The hub is a
  # reading surface now, so it has to keep the rule the river keeps.
  test "a story opened from a hobby card marks itself read, in place" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    feed = users(:one).feeds.create!(url: "https://example.com/wood.xml", sections: [ lens ])
    item = feed.feed_items.create!(guid: "1", title: "Bench hooks", url: "https://example.com/1")

    get section_path("hobbies")
    row = Nokogiri::HTML(response.body).at_css("##{ActionView::RecordIdentifier.dom_id(item, :hub)}")
    assert_equal "reader", row["data-controller"]
    assert_equal read_feed_item_path(item, surface: "hub"), row["data-reader-url-value"]
    assert_equal "reader#markRead", row.at_css("a")["data-action"]

    patch read_feed_item_path(item, surface: "hub"), as: :turbo_stream

    assert item.reload.read?
    assert_match ActionView::RecordIdentifier.dom_id(item, :hub), response.body
    assert_match(/Marked read/, response.body)
    assert_no_match(/reader-line/, response.body,
      "a river row rendered into a card would be the wrong shape")
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

  test "a hobby page clears its own pile, and only its own" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")
    other = Hobbies::Lens.find_or_create!("Baking")
    mine = users(:one).feeds.create!(url: "https://example.com/wood.xml", sections: [ lens ])
      .feed_items.create!(guid: "1", title: "Bench hooks")
    elsewhere = users(:one).feeds.create!(url: "https://example.com/bake.xml", sections: [ other ])
      .feed_items.create!(guid: "2", title: "Sourdough starters")

    get section_path(lens.slug)
    assert_select "form[action=?]", reader_read_all_path(hobby: lens.slug, return_to: section_path(lens.slug))

    post reader_read_all_path(hobby: lens.slug, return_to: section_path(lens.slug))

    assert_redirected_to section_path(lens.slug)
    assert mine.reload.read?
    assert_not elsewhere.reload.read?
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
