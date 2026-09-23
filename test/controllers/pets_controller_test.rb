require "test_helper"

class PetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @rex = create_pet(breed: "Golden retriever", born_on: 4.years.ago.to_date)
  end

  test "adding a pet creates her lens with her, so she is taggable immediately" do
    assert_difference -> { Pet.count } => 1, -> { Section.custom.count } => 1 do
      post pets_path, params: { pet: { name: "Luna", species: "cat" } }
    end

    luna = Pet.find_by!(name: "Luna")
    assert_redirected_to pet_path(luna)
    assert_equal "Luna", luna.section.name
    assert_equal sections(:people), luna.section.parent
    assert luna.section.custom?
  end

  test "both pet forms render, including the pronoun override beside the sex" do
    get new_pet_path
    assert_response :success
    assert_match "Follow the sex", response.body

    @rex.update!(sex: "female", pronoun: "they")
    get edit_pet_path(@rex)
    assert_response :success
    assert_select "select[name=?] option[selected][value=?]", "pet[pronoun]", "they"
  end

  test "the page and the flash call a pet what the record says, never always her" do
    @rex.update!(sex: "male", neutered: true)
    get pet_path(@rex)
    assert_response :success
    assert_match "Neutered male", response.body
    assert_match "What he eats, and since when.", response.body
    assert_no_match(/What she eats/, response.body)

    luna = create_pet(name: "Luna", species: "cat", sex: "female")
    get pet_path(luna)
    assert_match "What she eats, and since when.", response.body

    pip = create_pet(name: "Pip", species: "bird", died_on: Date.current)
    get pet_path(pip)
    assert_match "Their reminders have stopped. Everything filed under their name is still here.", response.body

    post pets_path, params: { pet: { name: "Pip", species: "bird" } }
    assert_equal "Pip added. Anything about them can be filed under their name now.", flash[:notice],
      "an unrecorded sex is not a reason to guess one"
  end

  test "the household box writes two visible grants; unticked writes none" do
    post pets_path, params: { pet: { name: "Luna", species: "cat" }, share_with_household: "1" }
    luna = Pet.find_by!(name: "Luna")

    subjects = users(:one).granted_access_grants.where(grantee: users(:two)).map(&:subject)
    assert_includes subjects, luna, "her page opens for the household"
    assert_includes subjects, luna.section, "and everything filed under her name comes with it"

    post pets_path, params: { pet: { name: "Marbles", species: "rabbit" } }
    marbles = Pet.find_by!(name: "Marbles")
    assert_empty users(:one).granted_access_grants.where(subject: marbles),
      "nothing is implied by living in the same house (D9)"
  end

  test "a second pet with the same name gets its own slug, never a shared lens" do
    post pets_path, params: { pet: { name: "Rex", species: "dog" } }
    second = Pet.where(name: "Rex").order(:id).last

    assert_not_equal @rex.section_id, second.section_id
    assert_equal "rex-2", second.section.slug
  end

  test "renaming a pet renames her lens but never its slug" do
    patch pet_path(@rex), params: { pet: { name: "Rexford" } }

    assert_equal "Rexford", @rex.reload.section.name
    assert_equal "rex", @rex.section.slug, "slugs are URLs; renaming one breaks bookmarks"
  end

  test "removing a pet removes her lens and leaves her items with their other tags" do
    lens_id = @rex.section_id
    event = users(:one).events.create!(title: "Vet", starts_at: 1.week.from_now)
    event.sections << [ sections(:health), @rex.section ]

    delete pet_path(@rex)
    assert_redirected_to section_path("people")

    assert_not Section.exists?(lens_id)
    assert_equal [ sections(:health) ], event.reload.sections.to_a
  end

  test "a pet's lens page is her lens page, not a group's members page" do
    get section_path(@rex.section.slug)
    assert_response :success
    assert_select "a", text: /Open Rex's page/
    assert_select "form[action=?]", people_memberships_path, count: 0
  end

  test "the group remove button never appears on a lens a pet owns" do
    get section_path(@rex.section.slug)
    assert_select "form[action=?]", group_path(@rex.section), count: 0

    delete group_path(@rex.section)
    assert Section.exists?(@rex.section_id), "Rex's lens is Rex's"
  end

  test "a pet shared with a household member opens for them but is not theirs to edit" do
    users(:one).granted_access_grants.create!(grantee: users(:two), subject: @rex)
    sign_in_as users(:two)

    get pet_path(@rex)
    assert_response :success

    patch pet_path(@rex), params: { pet: { name: "Nope" } }
    assert_response :not_found
    assert_equal "Rex", @rex.reload.name
  end

  test "an unshared pet is invisible to the household" do
    sign_in_as users(:two)
    get pet_path(@rex)
    assert_response :not_found
  end

  test "the People page carries pets, and a remembered one leaves the active strip" do
    get section_path("people")
    assert_response :success
    assert_select "a[href=?]", pet_path(@rex)
    assert_select "a[href=?]", new_pet_path

    @rex.update!(died_on: Date.current)
    get section_path("people")
    assert_select "h3", text: "Remembered"
  end

  test "a pet lens is not offered as a group of people" do
    get section_path("people")
    assert_select "a[href=?]", section_path(@rex.section.slug), { count: 0 },
      "a pet is not a group — her card is her own"
  end

  test "the pet page carries her radar, and a remembered pet's stops" do
    event = users(:one).events.create!(title: "Rex — vaccinations", starts_at: 1.year.ago)
    event.sections << @rex.section

    get pet_path(@rex)
    assert_select "h2", text: "Routine care"
    assert_match "Vaccinations", response.body

    @rex.update!(died_on: Date.current)
    get pet_path(@rex)
    assert_select "h2", { text: "Routine care", count: 0 }, "nothing nags about a pet who is gone"
  end

  test "pets join the Health page's household strip" do
    event = users(:one).events.create!(title: "Rex — wellness exam", starts_at: 2.weeks.from_now)
    event.sections << [ sections(:health), @rex.section ]

    get section_path("health")
    assert_select "a[href=?]", pet_path(@rex)
    assert_match "Wellness exam", response.body
  end
end
