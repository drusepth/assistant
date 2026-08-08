require "test_helper"

class PhotoTest < ActiveSupport::TestCase
  setup { @alice = users(:one) }

  test "requires an attached image" do
    photo = @alice.photos.new
    assert_not photo.valid?
    assert_includes photo.errors[:image], "must be attached"
  end

  test "rejects attachments that aren't images" do
    photo = @alice.photos.new
    photo.image.attach(io: StringIO.new("not an image"), filename: "letter.pdf", content_type: "application/pdf")

    assert_not photo.valid?
    assert_includes photo.errors[:image], "must be an image"
  end

  test "taken_at defaults to now so the timeline has an order before ingestion" do
    photo = create_photo(@alice)
    assert_in_delta Time.current.to_f, photo.taken_at.to_f, 5
  end

  test "untitled photos go by their date" do
    photo = create_photo(@alice)
    photo.update!(taken_at: Time.zone.local(2024, 3, 9, 12, 0))

    assert_equal "March 9, 2024", photo.display_title
    photo.update!(title: "Beach day")
    assert_equal "Beach day", photo.display_title
  end

  test "detects a duplicate of the same user's existing photo by checksum" do
    original = create_photo(@alice)
    copy = create_photo(@alice)

    assert copy.duplicate_of_existing?
    assert_not original.duplicate_of_existing?, "the older copy stays; only the newcomer reads as a duplicate of it"
  end

  test "the same bytes owned by another user are not a duplicate" do
    create_photo(@alice)
    bobs = create_photo(users(:two))

    assert_not bobs.duplicate_of_existing?
  end

  private
    def create_photo(user)
      user.photos.create!(image: fixture_upload)
    end

    def fixture_upload
      { io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg" }
    end
end
