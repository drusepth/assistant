require "test_helper"

class IngestPhotoJobTest < ActiveJob::TestCase
  setup { @alice = users(:one) }

  test "reads EXIF capture time and GPS, pre-renders variants, and marks the photo ready" do
    photo = create_photo("photo.jpg")

    IngestPhotoJob.perform_now(photo)
    photo.reload

    assert photo.ingest_ready?
    assert_equal Time.zone.local(2019, 7, 4, 16, 20, 0), photo.taken_at
    assert_in_delta 40.748500, photo.latitude.to_f, 0.0001
    assert_in_delta(-73.989833, photo.longitude.to_f, 0.0001)
    assert_equal 2, photo.image.blob.variant_records.count, "thumb and large are rendered ahead of first view"
  end

  test "a photo without EXIF keeps its upload-time taken_at and no location" do
    photo = create_photo("photo_no_exif.jpg")
    uploaded_at = photo.taken_at

    IngestPhotoJob.perform_now(photo)
    photo.reload

    assert photo.ingest_ready?
    assert_equal uploaded_at.to_i, photo.taken_at.to_i
    assert_not photo.coordinates?
  end

  test "an unreadable image fails visibly: status, message, and an /admin error" do
    photo = @alice.photos.new
    photo.image.attach(io: StringIO.new("not really a jpeg"), filename: "broken.jpg", content_type: "image/jpeg")
    photo.save!

    assert_difference("AppError.count") do
      assert_raises(StandardError) { IngestPhotoJob.perform_now(photo) }
    end
    photo.reload
    assert photo.ingest_failed?
    assert_match(/Couldn't process/, photo.ingest_error)
  end

  private
    def create_photo(fixture)
      @alice.photos.create!(image: {
        io: File.open(file_fixture(fixture)), filename: fixture, content_type: "image/jpeg"
      })
    end
end
