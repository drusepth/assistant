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
