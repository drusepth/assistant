require "test_helper"

class PhotosControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "batch upload creates a photo per file and queues ingestion" do
    assert_difference("Photo.count", 2) do
      assert_enqueued_jobs 2, only: IngestPhotoJob do
        post photos_path, params: { photos: { images: [
          fixture_file_upload("photo.jpg", "image/jpeg"),
          fixture_file_upload("photo_no_exif.jpg", "image/jpeg")
        ] } }
      end
    end
    assert_redirected_to photos_path
    assert_match "2 photos added", flash[:notice]
  end

  test "duplicates within a batch and against the library are skipped, not stored" do
    post photos_path, params: { photos: { images: [ fixture_file_upload("photo.jpg", "image/jpeg") ] } }

    assert_no_difference("Photo.count") do
      post photos_path, params: { photos: { images: [ fixture_file_upload("photo.jpg", "image/jpeg") ] } }
    end
    assert_match "1 duplicate skipped", flash[:notice]
  end

  test "non-image files are rejected with a count, never stored" do
    assert_no_difference("Photo.count") do
      post photos_path, params: { photos: { images: [ fixture_file_upload("sample.txt", "text/plain") ] } }
    end
    assert_match "wasn't an image", flash[:notice]
  end

  test "an empty submission is a friendly nudge, not an error" do
    post photos_path, params: { photos: { images: [ "" ] } }
    assert_redirected_to photos_path
    assert_equal "Choose some photos first.", flash[:alert]
  end

  test "the timeline shows own photos and grants, never strangers' photos" do
    own = create_photo(users(:one))
    hidden = create_photo(users(:two), fixture: "photo_no_exif.jpg")
    shared = create_photo(users(:two))
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: shared)

    get photos_path
    assert_response :success
    assert_select "a[href=?]", photo_path(own)
    assert_select "a[href=?]", photo_path(shared)
    assert_select "a[href=?]", photo_path(hidden), count: 0
  end

  test "the timeline filters by section" do
    tagged = create_photo(users(:one))
    tagged.sections << sections(:health)
    untagged = create_photo(users(:one), fixture: "photo_no_exif.jpg")

    get photos_path(section: "health")
    assert_select "a[href=?]", photo_path(tagged)
    assert_select "a[href=?]", photo_path(untagged), count: 0
  end

  test "the timeline filters by year" do
    old = create_photo(users(:one))
    old.update!(taken_at: Time.zone.local(2019, 7, 4))
    recent = create_photo(users(:one), fixture: "photo_no_exif.jpg")

    get photos_path(year: 2019)
    assert_select "a[href=?]", photo_path(old)
    assert_select "a[href=?]", photo_path(recent), count: 0
  end

  test "a shared photo's page renders for the grantee without owner controls" do
    photo = create_photo(users(:two))
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: photo)

    get photo_path(photo)
    assert_response :success
    assert_select "a[href=?]", edit_photo_path(photo), count: 0
  end

  test "an unshared photo's page is not found" do
    photo = create_photo(users(:two))
    get photo_path(photo)
    assert_response :not_found
  end

  test "location renders for the owner only" do
    photo = create_photo(users(:two))
    photo.update!(latitude: 40.7485, longitude: -73.9898)
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: photo)

    get photo_path(photo)
    assert_no_match "openstreetmap.org", response.body
  end

  test "editing is owner-only" do
    mine = create_photo(users(:one))
    patch photo_path(mine), params: { photo: { title: "Beach day", section_ids: [ sections(:people).id ] } }
    assert_redirected_to photo_path(mine)
    assert_equal "Beach day", mine.reload.title
    assert_includes mine.sections, sections(:people)

    theirs = create_photo(users(:two))
    patch photo_path(theirs), params: { photo: { title: "Nope" } }
    assert_response :not_found
    assert_nil theirs.reload.title
  end

  test "deleting is owner-only and removes the photo" do
    mine = create_photo(users(:one))
    assert_difference("Photo.count", -1) { delete photo_path(mine) }

    theirs = create_photo(users(:two))
    assert_no_difference("Photo.count") { delete photo_path(theirs) }
    assert_response :not_found
  end

  test "the map plots your located photos and links each pin to that place" do
    placed = create_photo(users(:one))
    placed.update!(latitude: 48.8566, longitude: 2.3522)
    unplaced = create_photo(users(:one), fixture: "photo_no_exif.jpg")

    get map_photos_path
    assert_response :success
    assert_select "a[href=?]", photos_path(near: "48.8566,2.3522")
    assert_match "1 photo", response.body
    assert_no_match photo_path(unplaced), response.body
  end

  test "the map never plots a shared photo — coordinates are owner-only" do
    theirs = create_photo(users(:two))
    theirs.update!(latitude: 51.5072, longitude: -0.1276)
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: theirs)

    get map_photos_path
    assert_response :success
    assert_select "a[href=?]", photos_path(near: "51.5072,-0.1276"), count: 0
    assert_match "No photos with a location yet", response.body
  end

  test "following a pin filters the timeline to that place, own photos only" do
    here = create_photo(users(:one))
    here.update!(latitude: 48.8566, longitude: 2.3522)
    elsewhere = create_photo(users(:one), fixture: "photo_no_exif.jpg")
    elsewhere.update!(latitude: 51.5072, longitude: -0.1276)

    shared = create_photo(users(:two))
    shared.update!(latitude: 48.8570, longitude: 2.3530)
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: shared)

    get photos_path(near: "48.8566,2.3522")
    assert_response :success
    assert_select "a[href=?]", photo_path(here)
    assert_select "a[href=?]", photo_path(elsewhere), count: 0
    assert_select "a[href=?]", photo_path(shared), count: 0
  end

  test "a nonsense place filter is ignored rather than an error" do
    photo = create_photo(users(:one))

    get photos_path(near: "over-there")
    assert_response :success
    assert_select "a[href=?]", photo_path(photo)
  end

  test "a failed ingest can be retried from the photo page" do
    photo = create_photo(users(:one))
    photo.update!(ingest_status: :failed, ingest_error: "boom")

    assert_enqueued_with(job: IngestPhotoJob) { post ingest_photo_path(photo) }
    assert photo.reload.ingest_queued?
  end

  private
    def create_photo(user, fixture: "photo.jpg")
      user.photos.create!(image: {
        io: File.open(file_fixture(fixture)), filename: fixture, content_type: "image/jpeg"
      })
    end
end
