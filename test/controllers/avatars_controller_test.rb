require "test_helper"

class AvatarsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "uploading a photo attaches it to the signed-in user" do
    patch avatar_path, params: { user: { avatar: fixture_file_upload("photo.jpg", "image/jpeg") } }

    assert_redirected_to settings_path
    assert_equal "Photo updated.", flash[:notice]
    assert users(:one).reload.avatar.attached?
  end

  test "a second upload replaces the first rather than stacking" do
    patch avatar_path, params: { user: { avatar: fixture_file_upload("photo.jpg", "image/jpeg") } }
    first = users(:one).reload.avatar.blob.id

    patch avatar_path, params: { user: { avatar: fixture_file_upload("photo_no_exif.jpg", "image/jpeg") } }

    assert_not_equal first, users(:one).reload.avatar.blob.id
  end

  test "a non-image is refused and nothing is attached" do
    patch avatar_path, params: { user: { avatar: fixture_file_upload("sample.txt", "text/plain") } }

    assert_redirected_to settings_path
    assert_match "PNG, JPEG, WEBP, or GIF", flash[:alert]
    assert_not users(:one).reload.avatar.attached?
  end

  test "an empty submission is a nudge, not an error" do
    patch avatar_path, params: { user: { avatar: "" } }

    assert_redirected_to settings_path
    assert_equal "Choose an image first.", flash[:alert]
  end

  test "removing the photo purges it" do
    users(:one).avatar.attach(io: file_fixture("photo.jpg").open, filename: "photo.jpg", content_type: "image/jpeg")

    delete avatar_path

    assert_redirected_to settings_path
    perform_enqueued_jobs
    assert_not users(:one).reload.avatar.attached?
  end

  test "the upload only ever touches the signed-in user, whatever else is posted" do
    patch avatar_path, params: { id: users(:two).id, user_id: users(:two).id,
      user: { avatar: fixture_file_upload("photo.jpg", "image/jpeg") } }

    assert users(:one).reload.avatar.attached?
    assert_not users(:two).reload.avatar.attached?
  end

  test "signing out closes the door" do
    delete session_path

    patch avatar_path, params: { user: { avatar: fixture_file_upload("photo.jpg", "image/jpeg") } }
    assert_redirected_to new_session_path
  end
end
