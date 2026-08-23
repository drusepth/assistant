require "test_helper"

# The Travel hub (D-travel-facet, docs/TRAVEL.md). Travel is an ordinary
# section — this pins the one thing about it that isn't ordinary: its lead
# panel reads the whole photo library rather than Travel-tagged items,
# because "where have I been" is a lens over every photo that knows where
# it was taken, not the subset somebody remembered to tag.
class TravelSectionTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the hub resolves its panel and plots every located photo, tagged or not" do
    assert_instance_of Sections::Panels::Travel, Sections::Panel.for(sections(:travel), users(:one))

    untagged = create_photo(users(:one))
    untagged.update!(latitude: 48.8566, longitude: 2.3522)

    get section_path("travel")
    assert_response :success
    assert_match "Latest places", response.body
    assert_select "a[href=?]", photos_path(near: "48.8566,2.3522")
    assert_select "a[href=?]", map_photos_path
    assert_match "1 photo", response.body
  end

  test "another member's shared photo is not on your map" do
    theirs = create_photo(users(:two))
    theirs.update!(latitude: 51.5072, longitude: -0.1276)
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: theirs)

    get section_path("travel")
    assert_response :success
    assert_select "a[href=?]", photos_path(near: "51.5072,-0.1276"), count: 0
  end

  test "an empty hub says why it is empty instead of showing a blank map" do
    create_photo(users(:one))

    get section_path("travel")
    assert_response :success
    assert_match "None of your 1 photos carry coordinates yet", response.body
    assert_select "a[href=?]", map_photos_path, count: 0
  end

  test "Travel is an ordinary section: items tag into it and browse there" do
    task = users(:one).tasks.create!(title: "Renew passport")
    task.sections << sections(:travel)

    get section_path("travel")
    assert_response :success
    assert_match "Renew passport", response.body
  end

  private
    def create_photo(user, fixture: "photo.jpg")
      user.photos.create!(image: {
        io: File.open(file_fixture(fixture)), filename: fixture, content_type: "image/jpeg"
      })
    end
end
