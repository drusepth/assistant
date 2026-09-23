require "test_helper"

class PetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @rex = create_pet(breed: "Golden retriever", born_on: 4.years.ago.to_date)
  end

  test "weight is in pounds, and in kilograms only for an owner who chose them" do
    get edit_pet_path(@rex)
    assert_select "label[for=pet_weight_lb]", text: "Weight (lb)"

    patch pet_path(@rex), params: { pet: { weight: "50" } }
    assert_equal BigDecimal("50"), @rex.reload.weight_lb
    follow_redirect!
    assert_match "50 lb", response.body

    users(:one).update!(measurement_system: "metric")
    get pet_path(@rex)
    assert_match "22.68 kg", response.body
    patch pet_path(@rex), params: { pet: { weight: "30.5" } }
    assert_equal BigDecimal("67.24"), @rex.reload.weight_lb

    patch pet_path(@rex), params: { pet: { weight: "" } }
    assert_nil @rex.reload.weight_lb
  end

  test "the header offers a task already tagged with her lens" do
    get pet_path(@rex)
    assert_select "a[href=?]", new_task_path(section_ids: [ @rex.section_id ]), text: "Add a task"

    get new_task_path(section_ids: [ @rex.section_id ])
    assert_response :success
  end

  test "adding a pet creates her lens with her, so she is taggable immediately" do
    assert_difference -> { Pet.count } => 1, -> { Section.custom.count } => 1 do
      post pets_path, params: { pet: { name: "Luna", species: "cat" } }
    end

    luna = Pet.find_by!(name: "Luna")
    assert_redirected_to pet_path(luna)
    assert_equal "Luna", luna.section.name
    assert_equal sections(:pets), luna.section.parent
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
    assert_redirected_to section_path("pets")

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

  test "the details card offers its owner an edit and names what is still blank" do
    get pet_path(@rex)
    assert_select "a[href=?]", edit_pet_path(@rex), text: "Edit", count: 2
    assert_select "a[href=?]", edit_pet_path(@rex), text: "Add sex, markings, weight, and microchip number"

    @rex.update!(sex: "male", color: "Gold", weight_lb: 66, microchip: "985112")
    get pet_path(@rex)
    assert_no_match(/Add sex/, response.body)
  end

  test "a household member the pet is shared with gets no edit on the details card" do
    users(:one).granted_access_grants.create!(grantee: users(:two), subject: @rex)
    sign_in_as users(:two)

    get pet_path(@rex)
    assert_select "a[href=?]", edit_pet_path(@rex), count: 0
  end

  test "typing a new vet makes them a contact, callable from the pet's page" do
    assert_difference -> { Person.count } => 1 do
      patch pet_path(@rex), params: { pet: { name: "Rex", vet_name: "Dr. Alvarez", vet_phone: "555-0100" } }
    end

    vet = @rex.reload.vet
    assert_equal "Dr. Alvarez", vet.name
    assert_equal "555-0100", vet.phone
    assert_equal "Vet", vet.relationship
    assert_equal users(:one), vet.user
    refute vet.keep_in_touch, "the vet goes in the Address Book, not the circle"

    get pet_path(@rex)
    assert_select "a[href=?]", "tel:555-0100"
  end

  test "typing a contact's name links them instead of making a twin" do
    existing = users(:one).people.create!(name: "Dr. Alvarez")

    assert_no_difference -> { Person.count } do
      patch pet_path(@rex), params: { pet: { vet_name: "dr. alvarez", vet_phone: "555-0100" } }
    end
    assert_equal existing, @rex.reload.vet
    assert_equal "555-0100", existing.reload.phone
  end

  test "clearing the vet box leaves no vet on file and the contact untouched" do
    vet = users(:one).people.create!(name: "Dr. Alvarez")
    @rex.update!(vet: vet)

    patch pet_path(@rex), params: { pet: { vet_name: "", vet_phone: "" } }
    assert_nil @rex.reload.vet
    assert Person.exists?(vet.id)
  end

  test "a pet that fails validation leaves no stray vet contact, and keeps what was typed" do
    assert_no_difference -> { Person.count } do
      patch pet_path(@rex), params: { pet: { name: "", vet_name: "Dr. Alvarez" } }
    end
    assert_response :unprocessable_entity
    assert_select "input[name=?][value=?]", "pet[vet_name]", "Dr. Alvarez"
  end

  test "an edit that doesn't carry the vet box leaves the vet alone" do
    vet = users(:one).people.create!(name: "Dr. Alvarez")
    @rex.update!(vet: vet)

    patch pet_path(@rex), params: { pet: { notes: "Scared of thunder" } }
    assert_equal vet, @rex.reload.vet
  end

  test "an unshared pet is invisible to the household" do
    sign_in_as users(:two)
    get pet_path(@rex)
    assert_response :not_found
  end

  test "the Pets hub carries pets, and a remembered one leaves the active strip" do
    assert_instance_of Sections::Panels::Pets, Sections::Panel.for(sections(:pets), users(:one))
    assert_equal sections(:pets), @rex.section.parent

    get section_path("pets")
    assert_response :success
    assert_select "a[href=?]", pet_path(@rex)
    assert_select "a[href=?]", new_pet_path

    @rex.update!(died_on: Date.current)
    get section_path("pets")
    assert_select "h3", text: "Remembered"
  end

  test "the Pets hub rolls up care only once the cards stop being an overview" do
    event = users(:one).events.create!(title: "Rex — vaccinations", starts_at: 1.year.ago)
    event.sections << @rex.section

    get section_path("pets")
    assert_select "h2", text: "Routine care", count: 0
    assert_match "vaccinations due", response.body, "the card names what's due"

    create_pet(name: "Luna", species: "cat")
    create_pet(name: "Bean", species: "rabbit")
    get section_path("pets")
    assert_select "h2", text: "Routine care"
  end

  test "the pet page keeps the rail on Pets and links back to the hub" do
    get pet_path(@rex)
    assert_select "a[href=?]", section_path("pets"), text: "← Pets"
    assert_select "aside a[href=?].bg-primary-600", section_path("pets")
    assert_select "a[href=?]", section_path(@rex.section.slug), text: /Everything filed under Rex/

    get section_path(@rex.section.slug)
    assert_select "aside a[href=?].bg-primary-600", section_path("pets")
  end

  test "a pet's chip reads as her name and opens her page" do
    task = users(:one).tasks.create!(title: "Buy dog food")
    task.sections << @rex.section

    get section_path("pets")
    assert_select "a.chip[href=?]", pet_path(@rex), text: "Rex"
    assert_select "a.chip", text: /Pets · Rex/, count: 0
  end

  test "the People page no longer carries pets" do
    get section_path("people")
    assert_response :success
    assert_select "a[href=?]", pet_path(@rex), count: 0
    assert_select "a[href=?]", new_pet_path, count: 0
    assert_select "a[href=?]", section_path(@rex.section.slug), { count: 0 },
      "a pet is not a group — her card is her own"
  end

  test "the pet tools live on the Pets hub, as buttons, and nowhere else in the rail" do
    get section_path("pets")
    assert_select "a.btn[href^=?]", new_tool_run_path("lost_pet"), text: "My pet is missing"
    assert_select "a.btn[href^=?]", new_tool_run_path("new_pet"), text: "Bringing a pet home"
    assert_select "h2", text: "Tools", count: 0

    %w[ people health ].each do |slug|
      get section_path(slug)
      assert_no_match "My pet is missing", response.body, slug
      assert_no_match "Bringing a pet home", response.body, slug
    end
  end

  test "with one pet the hub's tools already know which" do
    get section_path("pets")
    assert_select "a[href=?]", new_tool_run_path("vet_visit_prep", inputs: { pet_id: @rex.id })

    create_pet(name: "Luna", species: "cat")
    get section_path("pets")
    assert_select "a[href=?]", new_tool_run_path("vet_visit_prep")
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

  test "the cost card waits for a Pets envelope rather than asking for one" do
    get pet_path(@rex)
    assert_select "h2", { text: "Cost of care", count: 0 }

    users(:one).budget_categories.create!(name: "Pets", group: "needs")
    get pet_path(@rex)
    assert_select "h2", text: "Cost of care"
  end
end
