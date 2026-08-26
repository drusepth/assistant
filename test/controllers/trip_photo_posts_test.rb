require "test_helper"

# Posting photos to a trip (D-trip-companions): the explicit act that
# shares them — and the only way a companion ever sees them.
class TripPhotoPostsTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 6, 15, 12)
    sign_in_as users(:one)
    @trip = users(:one).trips.create!(name: "Boise", starts_on: "2026-06-01", ends_on: "2026-06-30")
    @trip.memberships.create!(user: users(:two))
    @photo = create_photo(users(:one), taken_at: Time.zone.local(2026, 6, 5, 10))
  end

  teardown { travel_back }

  test "the picker offers your photos from the trip's dates, and posting shares them" do
    outside_dates = create_photo(users(:one), taken_at: Time.zone.local(2026, 1, 1, 10))

    get new_trip_photo_post_path(@trip)
    assert_response :success
    assert_match "photo_#{@photo.id}", response.body
    assert_no_match "photo_#{outside_dates.id}", response.body

    assert_difference("TripPhoto.count", 1) do
      post trip_photo_posts_path(@trip), params: { photo_ids: [ @photo.id ] }
    end

    # The companion sees the posted photo — on the trip page and, through
    # the visibility path, on the photo page itself.
    sign_in_as users(:two)
    get trip_path(@trip)
    assert_select "a[href=?]", photo_path(@photo)
    get photo_path(@photo)
    assert_response :success
  end

  test "an unposted photo stays invisible to companions" do
    sign_in_as users(:two)
    get photo_path(@photo)
    assert_response :not_found
  end

  test "you can only post your own photos" do
    theirs = create_photo(users(:two), taken_at: Time.zone.local(2026, 6, 6, 10))

    assert_no_difference("TripPhoto.count") do
      post trip_photo_posts_path(@trip), params: { photo_ids: [ theirs.id ] }
    end
  end

  test "unposting is poster-or-owner, and leaves the photo in the library" do
    post trip_photo_posts_path(@trip), params: { photo_ids: [ @photo.id ] }
    posted = TripPhoto.sole

    sign_in_as users(:two)
    delete trip_photo_post_path(posted)
    assert_response :not_found

    sign_in_as users(:one)
    assert_no_difference("Photo.count") do
      assert_difference("TripPhoto.count", -1) { delete trip_photo_post_path(posted) }
    end
  end

  test "deleting a posted photo takes the post with it" do
    post trip_photo_posts_path(@trip), params: { photo_ids: [ @photo.id ] }

    assert_difference("TripPhoto.count", -1) { @photo.destroy! }
  end

  test "a page number past the end clamps instead of blanking" do
    get new_trip_photo_post_path(@trip, page: 99)
    assert_response :success
    assert_match "photo_#{@photo.id}", response.body
  end

  test "an outsider gets nothing" do
    sign_in_as users(:outsider)
    get new_trip_photo_post_path(@trip)
    assert_response :not_found
  end

  private
    def create_photo(user, taken_at:)
      user.photos.create!(
        image: { io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg" },
        taken_at: taken_at
      )
    end
end
