require "test_helper"

# The D30 sharing clause: a grant on an album exposes the album and the
# photos inside it — nothing more, and never another user's photo.
class AlbumVisibilityTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
    @bob = users(:two)
    @album = @alice.albums.create!(title: "Family trip")
    @in_album = create_photo(@alice)
    @album.photos << @in_album
    @loose = create_photo(@alice, fixture: "photo_no_exif.jpg")
  end

  test "no grant, no visibility" do
    assert_empty Album.visible_to(@bob)
    assert_empty Photo.visible_to(@bob)
  end

  test "an album grant exposes the album and exactly its photos" do
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @album)

    assert_includes Album.visible_to(@bob), @album
    assert_includes Photo.visible_to(@bob), @in_album
    assert_not_includes Photo.visible_to(@bob), @loose, "photos outside the album stay private"
  end

  test "photos added after the grant are covered; removed photos are not" do
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @album)

    late = create_photo(@alice, fixture: "photo_no_exif.jpg", seed: "different bytes")
    @album.photos << late
    assert late.visible_to?(@bob)

    @album.album_photos.where(photo: late).destroy_all
    assert_not late.reload.visible_to?(@bob)
  end

  test "revoking the grant hides album and photos again" do
    grant = AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @album)
    grant.destroy!

    assert_not @album.visible_to?(@bob)
    assert_not @in_album.visible_to?(@bob)
  end

  test "the grantor guard: an album can never leak a photo its owner didn't put there" do
    # Q15 groundwork — force a foreign photo into Alice's album, bypassing
    # the v1 same-owner validation, and grant Carol nothing from its owner.
    carols = users(:outsider).photos.new(image: {
      io: File.open(file_fixture("photo_no_exif.jpg")), filename: "c.jpg", content_type: "image/jpeg"
    })
    carols.save!(validate: true)
    AlbumPhoto.insert_all([ { album_id: @album.id, photo_id: carols.id,
      created_at: Time.current, updated_at: Time.current } ])
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @album)

    assert_not_includes Photo.visible_to(@bob), carols,
      "Alice's grant must not expose Carol's photo — the grantor isn't its owner"
  end

  private
    def create_photo(user, fixture: "photo.jpg", seed: nil)
      io = seed ? StringIO.new(File.binread(file_fixture(fixture)) + seed) : File.open(file_fixture(fixture))
      user.photos.create!(image: { io: io, filename: fixture, content_type: "image/jpeg" })
    end
end
