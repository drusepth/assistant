require "test_helper"

class PhotoPeopleControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @photo = create_photo(users(:one))
    @mom = users(:one).people.create!(name: "Mom")
  end

  test "the owner tags a person and the chip shows on the photo page" do
    assert_difference("PhotoPerson.count") do
      post photo_people_path, params: { photo_id: @photo.id, person_id: @mom.id }
    end

    get photo_path(@photo)
    assert_select "a[href=?]", person_path(@mom), text: "Mom"
  end

  test "tagging is idempotent" do
    2.times { post photo_people_path, params: { photo_id: @photo.id, person_id: @mom.id } }
    assert_equal 1, @photo.photo_people.count
  end

  test "you can only tag people you can see" do
    bobs_contact = users(:two).people.create!(name: "Bob's dentist")

    assert_no_difference("PhotoPerson.count") do
      post photo_people_path, params: { photo_id: @photo.id, person_id: bobs_contact.id }
    end
    assert_response :not_found
  end

  test "you can only tag your own photos" do
    bobs_photo = create_photo(users(:two), fixture: "photo_no_exif.jpg")

    post photo_people_path, params: { photo_id: bobs_photo.id, person_id: @mom.id }
    assert_response :not_found
  end

  test "untagging is for the photo's owner only" do
    tag = @photo.photo_people.create!(person: @mom)
    assert_difference("PhotoPerson.count", -1) { delete photo_person_path(tag) }

    bobs_photo = create_photo(users(:two), fixture: "photo_no_exif.jpg")
    bobs_person = users(:two).people.create!(name: "Cousin")
    bobs_tag = bobs_photo.photo_people.create!(person: bobs_person)

    delete photo_person_path(bobs_tag)
    assert_response :not_found
    assert PhotoPerson.exists?(bobs_tag.id)
  end

  test "a shared photo shows a viewer only the tagged people they can see" do
    @photo.photo_people.create!(person: @mom)
    AccessGrant.create!(grantor: users(:one), grantee: users(:two), subject: @photo)

    sign_in_as users(:two)
    get photo_path(@photo)
    assert_response :success
    assert_no_match "Mom", response.body, "an unshared Person must not leak through a photo tag"
  end

  test "the person page shows their photos and links to the filtered timeline" do
    @photo.photo_people.create!(person: @mom)
    other = create_photo(users(:one), fixture: "photo_no_exif.jpg")

    get person_path(@mom)
    assert_select "a[href=?]", photo_path(@photo)
    assert_select "a[href=?]", photo_path(other), count: 0
    assert_select "a[href=?]", photos_path(person: @mom.id)

    get photos_path(person: @mom.id)
    assert_select "a[href=?]", photo_path(@photo)
    assert_select "a[href=?]", photo_path(other), count: 0
  end

  test "the admin overview reports storage service and per-member counts" do
    get admin_root_path
    assert_response :success
    assert_match "Active Storage service: test", response.body
    assert_match "1 photo", response.body
  end

  private
    def create_photo(user, fixture: "photo.jpg")
      user.photos.create!(image: {
        io: File.open(file_fixture(fixture)), filename: fixture, content_type: "image/jpeg"
      })
    end
end
