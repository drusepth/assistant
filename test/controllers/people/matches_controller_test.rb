require "test_helper"

# D-person-picker: the combobox's suggestions, as option rows.
class People::MatchesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "answers with matching people and an offer to add the typed name" do
    rosa = users(:one).people.create!(name: "Rosa Diaz")

    get people_matches_path(for: "circle", q: "ros")
    assert_response :success
    assert_select "li[role=option][data-person-id=?][data-name=?]", rosa.id.to_s, "Rosa Diaz"
    assert_select "li[role=option]:not([data-person-id])[data-name=?]", "ros"
  end

  test "doesn't offer to add a name someone already has, even someone already there" do
    users(:one).people.create!(name: "Rosa", keep_in_touch: true)

    get people_matches_path(for: "circle", q: "rosa")
    assert_select "li[role=option]", false
  end

  test "a group's suggestions leave out its members" do
    group = People::Group.find_or_create!("Book club")
    users(:one).people.create!(name: "Rosa In").sections << group
    out = users(:one).people.create!(name: "Rosa Out")

    get people_matches_path(for: "group", section_id: group.id, q: "rosa")
    assert_select "li[data-person-id]", 1
    assert_select "li[data-person-id=?]", out.id.to_s
  end

  test "a photo's suggestions need the viewer's own photo" do
    theirs = users(:two).photos.create!(image: {
      io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg"
    })

    get people_matches_path(for: "photo", photo_id: theirs.id, q: "a")
    assert_response :not_found
  end

  test "an empty query answers with suggestions instead of a search" do
    users(:one).people.create!(name: "Chatty", last_contacted_on: 2.days.ago.to_date)

    get people_matches_path(for: "circle", q: "")
    assert_match "Suggestions", response.body
    assert_select "li[role=option][data-name=Chatty]", text: /Talked/
  end

  test "the matched text is bold, and a repeated name carries a hint to tell them apart" do
    users(:one).people.create!(name: "Sam Lee", email: "sam@work.test")
    users(:one).people.create!(name: "Sam Lee", phone: "5035550142")

    get people_matches_path(for: "circle", q: "lee")
    assert_select "li[role=option] strong", text: "Lee", count: 2
    assert_match "sam@work.test", response.body
    assert_match "(503) 555-0142", response.body
  end

  test "a form field's suggestions reach anyone visible, nobody left out" do
    users(:one).people.create!(name: "Rosa", keep_in_touch: true)

    get people_matches_path(for: "any", q: "ros")
    assert_select "li[data-person-id]", 1
  end
end
