require "test_helper"

class AlbumsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "creates, updates, and deletes an album" do
    assert_difference("Album.count") do
      post albums_path, params: { album: { title: "Garden", description: "Through the seasons" } }
    end
    album = Album.last
    assert_redirected_to album_path(album)

    patch album_path(album), params: { album: { title: "The garden" } }
    assert_equal "The garden", album.reload.title

    assert_difference("Album.count", -1) { delete album_path(album) }
  end

  test "adds and removes selected photos" do
    album = users(:one).albums.create!(title: "Trip")
    mine = create_photo(users(:one))
    also_mine = create_photo(users(:one), fixture: "photo_no_exif.jpg")
    bobs = create_photo(users(:two))

    post add_photos_album_path(album), params: { photo_ids: [ mine.id, also_mine.id, bobs.id ] }
    assert_equal [ mine.id, also_mine.id ].sort, album.reload.photo_ids.sort,
      "another user's photo can't be added to my album"

    delete remove_photos_album_path(album), params: { photo_ids: [ also_mine.id ] }
    assert_equal [ mine.id ], album.reload.photo_ids
  end

  test "uploading from an album page files the new photos into it" do
    album = users(:one).albums.create!(title: "Trip")

    post photos_path, params: { photos: { album_id: album.id, images: [
      fixture_file_upload("photo.jpg", "image/jpeg")
    ] } }

    assert_equal 1, album.reload.photos.count
  end

  test "another user's album can't be managed or uploaded into" do
    album = users(:two).albums.create!(title: "Bob's")

    patch album_path(album), params: { album: { title: "Hijacked" } }
    assert_response :not_found

    post photos_path, params: { photos: { album_id: album.id, images: [
      fixture_file_upload("photo.jpg", "image/jpeg")
    ] } }
    assert_response :not_found
    assert_equal "Bob's", album.reload.title
  end

  test "the index shows own albums and albums shared with me" do
    mine = users(:one).albums.create!(title: "Mine")
    shared = users(:two).albums.create!(title: "Bob's shared")
    hidden = users(:two).albums.create!(title: "Bob's private")
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: shared)

    get albums_path
    assert_select "a[href=?]", album_path(mine)
    assert_select "a[href=?]", album_path(shared)
    assert_select "a[href=?]", album_path(hidden), count: 0
  end

  test "a shared album's page renders its photos for the grantee, without owner controls" do
    album = users(:two).albums.create!(title: "Bob's shared")
    photo = create_photo(users(:two))
    album.photos << photo
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: album)

    get album_path(album)
    assert_response :success
    assert_select "a[href=?]", photo_path(photo)
    assert_select "a[href=?]", edit_album_path(album), count: 0
  end

  test "sharing with everyone in the household creates a grant per member, idempotently" do
    album = users(:one).albums.create!(title: "Family")
    AccessGrant.create!(grantor: users(:one), grantee: users(:two), subject: album)

    assert_no_difference("AccessGrant.count") do
      post access_grants_path, params: { subject_type: "Album", subject_id: album.id, everyone: 1 }
    end
    assert album.visible_to?(users(:two))
    assert_not album.visible_to?(users(:outsider)), "other households are never included"
  end

  private
    def create_photo(user, fixture: "photo.jpg")
      user.photos.create!(image: {
        io: File.open(file_fixture(fixture)), filename: fixture, content_type: "image/jpeg"
      })
    end
end
