require "test_helper"

class AlbumTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
    @album = @alice.albums.create!(title: "Summer")
  end

  test "cover falls back to the newest photo when none is chosen" do
    older = create_photo(@alice, taken_at: 2.years.ago)
    newer = create_photo(@alice, fixture: "photo_no_exif.jpg", taken_at: 1.day.ago)
    @album.photos << [ older, newer ]

    assert_equal newer, @album.cover
    @album.update!(cover_photo: older)
    assert_equal older, @album.cover
  end

  test "the cover must be the owner's own photo" do
    bobs = create_photo(users(:two))
    @album.cover_photo = bobs

    assert_not @album.valid?
    assert_includes @album.errors[:cover_photo], "must be one of your photos"
  end

  test "albums hold only the owner's photos (Q15 is future work)" do
    bobs = create_photo(users(:two))
    membership = @album.album_photos.new(photo: bobs)

    assert_not membership.valid?
    assert_includes membership.errors[:photo], "must belong to the album's owner"
  end

  test "deleting an album never deletes its photos" do
    photo = create_photo(@alice)
    @album.photos << photo

    assert_no_difference("Photo.count") { @album.destroy! }
    assert Photo.exists?(photo.id)
  end

  test "deleting a photo clears it from albums, covers included" do
    photo = create_photo(@alice)
    @album.photos << photo
    @album.update!(cover_photo: photo)

    photo.destroy!
    assert_empty @album.reload.photos
    assert_nil @album.cover_photo
  end

  private
    def create_photo(user, fixture: "photo.jpg", taken_at: nil)
      photo = user.photos.create!(image: {
        io: File.open(file_fixture(fixture)), filename: fixture, content_type: "image/jpeg"
      })
      photo.update!(taken_at: taken_at) if taken_at
      photo
    end
end
