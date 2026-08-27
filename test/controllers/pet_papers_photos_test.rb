require "test_helper"

# W4 of docs/PETS_PLAN.md: papers and pictures, both of them primitives the
# app already understood — the pet's lens is all that was missing.
class PetPapersPhotosTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @rex = create_pet
  end

  def document(title, **attributes)
    doc = users(:one).documents.create!(title: title, **attributes)
    doc.sections << @rex.section
    doc
  end

  def photo(sections: [ @rex.section ])
    photo = users(:one).photos.create!(image: {
      io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg"
    })
    photo.sections << sections if sections.any?
    photo
  end

  test "policy-shaped papers lead, because they're what you need at the worst moment" do
    document("Adoption papers")
    policy = document("Pet insurance policy 2026")

    assert_equal policy, Pets::Papers.for(@rex, users(:one)).first
    assert Pets::Papers.policy?(policy)
  end

  test "the papers card reads through visible_to" do
    document("Vaccination record")
    assert_empty Pets::Papers.for(@rex, users(:two)), "no grant, no sight"
  end

  test "her photos are ordinary tagged photos — no join table" do
    hers = photo
    photo(sections: [ sections(:health) ])

    get pet_path(@rex)
    assert_response :success
    assert_equal [ hers ], @rex.items(Photo, users(:one)).to_a
  end

  test "a captioner may suggest a pet lens but never file one for you" do
    subject = photo(sections: [])
    subject.update!(suggested_sections: [ @rex.section.slug, "health" ])

    assert_includes subject.suggested_section_records, @rex.section, "it may offer"
    assert_not_includes subject.auto_filable_section_records, @rex.section,
      "a model confidently tagging the neighbour's dog as Rex is the Q8 lesson"
    assert_includes subject.auto_filable_section_records, sections(:health)
  end

  test "the memorial album is offered only once she's gone, and gathers her photos" do
    hers = photo
    get pet_path(@rex)
    assert_select "form[action=?]", memorial_pet_album_path(@rex), count: 0

    @rex.update!(died_on: Date.current, born_on: Date.new(2018, 3, 1))
    get pet_path(@rex)
    assert_select "form[action=?]", memorial_pet_album_path(@rex)

    post memorial_pet_album_path(@rex)
    album = users(:one).albums.sole
    assert_equal "Rex", album.title
    assert_equal "Rex, 2018–#{Date.current.year}.", album.description
    assert_equal [ hers ], album.photos.to_a
  end

  test "a memorial album with no photos says so instead of making an empty one" do
    @rex.update!(died_on: Date.current)
    post memorial_pet_album_path(@rex)

    assert_empty users(:one).albums
    assert_match "No photos are tagged Rex", flash[:alert]
  end
end
