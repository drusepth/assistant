require "test_helper"

class PetVaccinationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    sign_in_as @owner
    @rex = create_pet(user: @owner)
  end

  def visit_params(rows, **visit)
    { log: { given_on: 1.week.ago.to_date.iso8601, **visit, rows: rows } }
  end

  test "the log form is a checklist of her species' vaccines plus free rows" do
    get new_pet_vaccination_path(@rex)
    assert_response :success
    assert_select "input[name='log[rows][rabies][include]']"
    assert_select "input[name='log[rows][dhpp][include]']"
    assert_select "input[name='log[rows][fvrcp][include]']", { count: 0 }, "a dog has no FVRCP"
    assert_select "input[name='log[rows][other_0][name]']"
    assert_select "input[name='log[rows][rabies][duration_months]'][checked]:not([value=''])", { count: 0 },
      "no lifetime is preselected — the certificate or the owner knows"
  end

  test "one visit logs several vaccines, each on its own clock" do
    assert_difference -> { @rex.pet_vaccinations.count }, 3 do
      post pet_vaccinations_path(@rex), params: visit_params(
        { "rabies" => { include: "1", duration_months: "36", tag_number: "R-2291" },
          "bordetella" => { include: "1", due_on: 6.months.from_now.to_date.iso8601, duration_months: "12" },
          "dhpp" => { include: "0" },
          "other_0" => { include: "1", name: "Leishmaniasis" } },
        administered_by: "Riverside Animal Hospital")
    end
    assert_redirected_to pet_vaccinations_path(@rex)

    rabies = @rex.pet_vaccinations.find_by!(vaccine_key: "rabies")
    assert_equal 1.week.ago.to_date + 36.months, rabies.due_on
    assert_equal "R-2291", rabies.tag_number
    assert_equal "Riverside Animal Hospital", rabies.given_by

    bordetella = @rex.pet_vaccinations.find_by!(vaccine_key: "bordetella")
    assert_equal 6.months.from_now.to_date, bordetella.due_on, "the certificate's date wins"
    assert_nil bordetella.duration_months

    assert @rex.pet_vaccinations.exists?(vaccine_key: nil, name: "Leishmaniasis")
  end

  test "all or nothing: one bad row saves none and re-renders what was typed" do
    assert_no_difference -> { PetVaccination.count } do
      post pet_vaccinations_path(@rex), params: visit_params(
        { "rabies" => { include: "1", lot_number: "L-77" },
          "dhpp" => { include: "1", due_on: 1.year.ago.to_date.iso8601 } })
    end
    assert_response :unprocessable_entity
    assert_select "input[name='log[rows][rabies][lot_number]'][value='L-77']"
  end

  test "nothing ticked is an error, not an empty save" do
    post pet_vaccinations_path(@rex), params: visit_params({ "rabies" => { include: "0" } })
    assert_response :unprocessable_entity
  end

  test "a key the form couldn't have rendered is dropped" do
    post pet_vaccinations_path(@rex), params: visit_params({ "fvrcp" => { include: "1" } })
    assert_response :unprocessable_entity
    assert_equal 0, PetVaccination.count
  end

  test "an uploaded certificate becomes a document filed under Health and her name" do
    post pet_vaccinations_path(@rex), params: visit_params(
      { "rabies" => { include: "1" } }, certificate: fixture_file_upload("photo.jpg", "image/jpeg"))

    dose = @rex.pet_vaccinations.sole
    assert dose.document
    assert_includes dose.document.sections, @rex.section
    assert_includes dose.document.sections, sections(:health)
  end

  test "logging from a visit links the doses and marks the visit as a vaccination visit" do
    visit = @owner.events.create!(title: "Rex — vet", starts_at: 3.days.ago)
    visit.sections << @rex.section

    get new_pet_vaccination_path(@rex, event_id: visit.id)
    assert_select "input[name='log[given_on]'][value=?]", 3.days.ago.to_date.iso8601

    post pet_vaccinations_path(@rex), params: visit_params({ "rabies" => { include: "1" } }, event_id: visit.id)
    assert_equal visit, @rex.pet_vaccinations.sole.event
    assert_equal "pet_vaccinations", visit.reload.care_kind
  end

  test "the pet page shows the card, with reactions never collapsed" do
    @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "leptospirosis", given_on: 1.month.ago.to_date,
      due_on: 11.months.from_now.to_date, reaction: "Facial swelling")

    get pet_path(@rex)
    assert_select "h2", text: "Vaccinations"
    assert_match "Reacted to Leptospirosis", response.body
    assert_match "Facial swelling", response.body
    assert_match "No record of Rabies and DHPP", response.body
  end

  test "a household member the pet is shared with can log, and change only their own doses" do
    mine = @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 1.year.ago.to_date)
    @owner.granted_access_grants.create!(grantee: users(:two), subject: @rex)
    sign_in_as users(:two)

    post pet_vaccinations_path(@rex), params: visit_params({ "bordetella" => { include: "1" } })
    theirs = @rex.pet_vaccinations.find_by!(vaccine_key: "bordetella")
    assert_equal users(:two), theirs.user

    patch pet_vaccination_path(@rex, mine), params: { pet_vaccination: { lot_number: "nope" } }
    assert_nil mine.reload.lot_number

    patch pet_vaccination_path(@rex, theirs), params: { pet_vaccination: { lot_number: "B-1" } }
    assert_equal "B-1", theirs.reload.lot_number
  end

  test "a pet nobody shared is not found" do
    sign_in_as users(:two)
    get pet_vaccinations_path(@rex)
    assert_response :not_found
  end

  test "editing: a changed date replaces the duration; an unchanged one keeps it" do
    dose = @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 1.month.ago.to_date, duration_months: 12)

    patch pet_vaccination_path(@rex, dose), params: { pet_vaccination: { due_on: dose.due_on.iso8601, duration_months: "36" } }
    assert_equal 1.month.ago.to_date + 36.months, dose.reload.due_on

    patch pet_vaccination_path(@rex, dose), params: { pet_vaccination: { due_on: 2.years.from_now.to_date.iso8601, duration_months: "36" } }
    assert_equal 2.years.from_now.to_date, dose.reload.due_on
    assert_nil dose.duration_months
  end

  test "removing a dose" do
    dose = @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 1.month.ago.to_date)
    delete pet_vaccination_path(@rex, dose)
    assert_not PetVaccination.exists?(dose.id)
  end

  test "the full record lists every dose under its vaccine" do
    @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 4.years.ago.to_date, product: "Imrab 3")
    @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 1.year.ago.to_date, lot_number: "L-9")

    get pet_vaccinations_path(@rex)
    assert_response :success
    assert_match "Imrab 3", response.body
    assert_match "lot L-9", response.body
  end

  test "the shareable record leaves out reactions and notes, and serves certificates only through a live token" do
    document = @owner.documents.create!(title: "Rabies certificate", file: fixture_file_upload("photo.jpg", "image/jpeg"))
    @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 1.month.ago.to_date,
      due_on: 3.years.from_now.to_date, tag_number: "R-2291", reaction: "Hives", notes: "Private note", document: document)

    get record_pet_vaccinations_path(@rex)
    assert_response :success
    assert_no_match "Hives", response.body

    post share_links_path, params: { subject_type: "Pet", subject_id: @rex.id, expires_in_days: "7" }
    link = @owner.share_links.sole
    assert_equal @rex, link.subject

    sign_out
    get shared_path(link.token)
    assert_response :success
    assert_match "R-2291", response.body
    assert_no_match "Hives", response.body
    assert_no_match "Private note", response.body

    dose = @rex.pet_vaccinations.sole
    get shared_certificate_path(link.token, dose)
    assert_response :success
    assert_equal "image/jpeg", response.media_type

    link.destroy
    get shared_certificate_path(link.token, dose)
    assert_response :not_found
  end

  test "only the owner can share a pet's record" do
    @owner.granted_access_grants.create!(grantee: users(:two), subject: @rex)
    sign_in_as users(:two)
    post share_links_path, params: { subject_type: "Pet", subject_id: @rex.id }
    assert_response :not_found
    assert_equal 0, ShareLink.count
  end

  test "a pet's past visit offers the vaccine log and a vaccination-visit option" do
    visit = @owner.events.create!(title: "Rex — vet", starts_at: 3.days.ago)
    visit.sections << @rex.section

    get event_path(visit)
    assert_select "a[href=?]", new_pet_vaccination_path(@rex, event_id: visit.id)
    assert_select "select[name='event[care_kind]'] option[value='pet_vaccinations']"
  end

  test "a Book link's care kind survives into the saved event" do
    get new_event_path(title: "Rex — vaccinations", care_kind: "pet_vaccinations", section_ids: [ @rex.section_id ])
    assert_select "input[type=hidden][name='event[care_kind]'][value='pet_vaccinations']"
  end

  test "a document's saved dose links to her record" do
    document = @owner.documents.create!(title: "Rabies certificate")
    dose = @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 1.month.ago.to_date, document: document)
    document.document_items.create!(item: dose, fingerprint: "pet_vaccination:x")

    get document_path(document)
    assert_select "a[href=?]", pet_vaccinations_path(@rex), text: "Rabies"
  end

  # ── Pre-merge polish ─────────────────────────────────────────────────

  test "one Book button covers everything due, marked as a vaccination visit" do
    @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 3.years.ago.to_date, due_on: 10.days.from_now.to_date)
    @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "dhpp", given_on: 3.years.ago.to_date, due_on: 20.days.from_now.to_date)

    get pet_path(@rex)
    booking = new_event_path(Pets::VaccineStatus.new(@rex, viewer: @owner).booking_params)
    assert_select "a[href=?]", booking, text: "Book a visit", count: 1
    assert_match "Rex — vaccinations (Rabies, DHPP)", CGI.unescape(booking)
    assert_select "a", text: "Book", count: 0
    assert_match "Rabies and DHPP need doing", response.body
  end

  test "a pet who has died keeps her record as history, with no states and no buttons" do
    @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 3.years.ago.to_date, due_on: 1.month.ago.to_date)
    @rex.update!(died_on: 1.week.ago.to_date)

    get pet_path(@rex)
    assert_select "h2", text: "Vaccinations"
    assert_no_match "Overdue", response.body
    assert_no_match "Book a visit", response.body
    assert_no_match "No record of", response.body
    assert_select "a", text: "Log vaccines", count: 0

    get pet_vaccinations_path(@rex)
    assert_no_match "Overdue", response.body
  end

  test "a species with no vaccine list gets a sidebar link instead of an empty card" do
    nemo = create_pet(user: @owner, name: "Nemo", species: "fish")
    get pet_path(nemo)
    assert_select "h2", text: "Vaccinations", count: 0
    assert_select "nav a[href=?]", new_pet_vaccination_path(nemo), text: "Log a vaccine"

    nemo.pet_vaccinations.create!(user: @owner, name: "Koi herpes", given_on: 1.month.ago.to_date)
    get pet_path(nemo)
    assert_select "h2", text: "Vaccinations"
    assert_select "nav a", text: "Log a vaccine", count: 0
  end

  test "the empty card's upload link files the certificate under Health and her name" do
    get pet_path(@rex)
    upload = new_document_path(section_ids: [ @rex.section_id, sections(:health).id ])
    assert_select "a[href=?]", upload

    get upload
    assert_select "input[type=hidden][name='document[section_ids][]'][value=?]", @rex.section_id.to_s
    assert_select "input[type=hidden][name='document[section_ids][]'][value=?]", sections(:health).id.to_s
  end

  test "typed vaccine rows arrive one at a time, and a filled one always shows" do
    get new_pet_vaccination_path(@rex)
    assert_select "input[name='log[rows][other_0][include]'][data-reveals-1]"
    assert_select "div.hidden input[name='log[rows][other_0][include]']", count: 0
    assert_select "div.hidden input[name='log[rows][other_1][include]']"

    post pet_vaccinations_path(@rex), params: visit_params({ "other_1" => { include: "1", name: "" }, "dhpp" => { include: "1", due_on: 1.year.ago.to_date.iso8601 } })
    assert_select "div.hidden input[name='log[rows][other_1][include]']", count: 0
  end

  test "with no vet in the Address Book the form asks for a name, not a pick from nothing" do
    get new_pet_vaccination_path(@rex)
    assert_select "select[name='log[vet_id]']", count: 0
    assert_select "input[name='log[administered_by]']"

    @rex.update!(vet: @owner.people.create!(name: "Dr. Okafor", relationship: "Vet"))
    get new_pet_vaccination_path(@rex)
    assert_select "select[name='log[vet_id]'] option[selected]", text: "Dr. Okafor"
    assert_select "input[name='log[administered_by]']"
  end

  test "each row's length buttons defer to a typed date" do
    get new_pet_vaccination_path(@rex)
    assert_select "div[data-controller=vaccine-row] input[name='log[rows][rabies][due_on]'][data-vaccine-row-target=date]"
    assert_select "fieldset[data-vaccine-row-target=durations]"
  end

  test "a kennel link defaults to expiring in 30 days" do
    get record_pet_vaccinations_path(@rex)
    assert_select "select[name=expires_in_days] option[selected][value='30']"
  end

  test "the Pets hub roll-up shows vaccines beside the radar" do
    @rex.pet_vaccinations.create!(user: @owner, vaccine_key: "rabies", given_on: 3.years.ago.to_date, due_on: 10.days.from_now.to_date)
    create_pet(user: @owner, name: "Luna", species: "cat")
    create_pet(user: @owner, name: "Bean", species: "rabbit")

    get section_path("pets")
    assert_select "h2", text: "Routine care"
    assert_match "Rabies — due soon", response.body
  end
end
