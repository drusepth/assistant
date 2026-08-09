require "test_helper"

# The "everywhere" half of D-user-avatars: an uploaded photo is worth
# nothing if it only shows on the page you uploaded it from. Each surface
# that names a person is checked once here, so a new one that hand-rolls an
# initials circle instead of Ui::AvatarComponent gets caught.
class AvatarSurfacesTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:one)
    @bob = users(:two)
    # Distinct filenames: the variant URL carries them, so an assertion can
    # say *whose* face is on the page, not merely that a face is.
    attach_avatar @alice, "alice.jpg"
    attach_avatar @bob, "bob.jpg"
    sign_in_as @alice
  end

  test "the sidebar wears your own photo on every page" do
    get root_path
    assert_avatar_of @alice
  end

  test "the dashboard's household strip wears everyone's" do
    get root_path
    assert_avatar_of @bob
  end

  test "the household members list wears everyone's" do
    get household_path
    assert_avatar_of @bob
  end

  test "the settings photo card previews your own" do
    get settings_path
    assert_avatar_of @alice
  end

  test "a contact linked to a household account wears that member's photo" do
    @alice.people.create!(name: "Bob Smith", linked_user: @bob)

    get people_path
    assert_avatar_of @bob
  end

  test "a contact who is only a contact keeps initials — no borrowed face" do
    @alice.people.create!(name: "Dana Reed")

    get people_path
    assert_select "img", count: 1 # the sidebar's own avatar, and nothing else
    assert_match "DR", response.body
  end

  test "the sharing controls name the grantee with their photo" do
    note = @alice.notes.create!(body: "Shared")
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: note)

    get note_path(note)
    assert_avatar_of @bob
  end

  # The "from Bea" marker on a borrowed item is one partial reaching every
  # primitive's row and show page, so it gets checked on both shapes.
  test "an item shared with you is attributed to its owner's face in lists" do
    note = @bob.notes.create!(body: "Bob's note, shared with Alice")
    AccessGrant.create!(grantor: @bob, grantee: @alice, subject: note)

    get notes_path
    assert_avatar_of @bob
  end

  test "…and on the item's own page" do
    task = @bob.tasks.create!(title: "Bob's task")
    AccessGrant.create!(grantor: @bob, grantee: @alice, subject: task)

    get task_path(task)
    assert_avatar_of @bob
  end

  test "your own items carry no face — the default needs no mark" do
    @alice.notes.create!(body: "Mine alone")

    get notes_path
    assert_select "img", count: 1 # the sidebar, and nothing else
  end

  test "a shared event on the calendar says whose day it is" do
    event = @bob.events.create!(title: "Bob's dentist", starts_at: Time.current.change(hour: 9))
    AccessGrant.create!(grantor: @bob, grantee: @alice, subject: event)

    get calendar_path
    assert_avatar_of @bob
  end

  test "a shared photo is marked in a grid that otherwise looks like yours" do
    photo = @bob.photos.build(title: "Bob's photo")
    photo.image.attach(io: file_fixture("photo.jpg").open, filename: "p.jpg", content_type: "image/jpeg")
    photo.save!
    AccessGrant.create!(grantor: @bob, grantee: @alice, subject: photo)

    get photos_path
    assert_avatar_of @bob
  end

  test "a shared album card and its page name the owner" do
    album = @bob.albums.create!(title: "Bob's album")
    AccessGrant.create!(grantor: @bob, grantee: @alice, subject: album)

    get albums_path
    assert_avatar_of @bob

    get album_path(album)
    assert_avatar_of @bob
  end

  test "a credential shared into your vault names its owner in the list and on its page" do
    Keyring.initialize_for(@alice, "password")
    Keyring.initialize_for(@bob, "password")
    credential = @bob.credentials.create!(name: "Bob's bank", kind: "login", username: "bob")
    AccessGrant.create!(grantor: @bob, grantee: @alice, subject: credential)

    get credentials_path
    assert_avatar_of @bob

    get credential_path(credential)
    assert_avatar_of @bob
  end

  test "the admin error log puts a face to the account that hit it" do
    AppError.create!(user: @bob, source: "job", error_class: "RuntimeError", message: "boom")

    get admin_errors_path
    assert_avatar_of @bob
  end

  private
    def attach_avatar(user, filename)
      user.avatar.attach(io: file_fixture("photo.jpg").open, filename: filename, content_type: "image/jpeg")
    end

    def assert_avatar_of(user)
      assert_response :success
      assert_select "img[src$=?]", user.avatar.filename.to_s,
        message: "expected #{user.name}'s avatar on this page"
    end
end
