require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "log_contact stamps today on your own person only" do
    person = users(:one).people.create!(name: "Mom")
    patch log_contact_person_path(person)
    assert_equal Date.current, person.reload.last_contacted_on

    other = users(:two).people.create!(name: "Bob's friend")
    patch log_contact_person_path(other)
    assert_response :not_found
    assert_nil other.reload.last_contacted_on
  end

  test "creates a person linked to a household member" do
    assert_difference("Person.count") do
      post people_path, params: {
        person: { name: "Bob Smith", relationship: "Husband", linked_user_id: users(:two).id, section_ids: [ sections(:health).id ] }
      }
    end
    assert_equal users(:two), Person.last.linked_user
  end

  test "quick-adding a name and note queues auto-sorting" do
    assert_enqueued_with(job: CategorizePersonJob) do
      post people_path, params: { person: { name: "Dr. Alvarez", notes: "My cardiologist." } }
    end
  end

  test "hand-tagged people are not auto-sorted" do
    assert_no_enqueued_jobs(only: CategorizePersonJob) do
      post people_path, params: { person: { name: "Bob", section_ids: [ sections(:health).id ] } }
    end
  end

  test "new form is quick capture" do
    get new_person_path
    assert_response :success
    assert_match "Who are they?", response.body
  end

  # D-people-auto-filing: the edit form used to open on two dozen section
  # checkboxes. They're still reachable — inside the shared Advanced drawer —
  # just not the first thing you meet, and the closed line says who filed them.
  test "the edit form folds filing away and says who's doing it" do
    person = users(:one).people.create!(name: "Mom")

    get edit_person_path(person)
    assert_response :success
    assert_select "details summary", /Advanced/
    assert_match "your assistant files this one", response.body
  end

  test "…and names the sections once they're filed" do
    person = users(:one).people.create!(name: "Dr. Alvarez")
    person.sections << sections(:health)

    get edit_person_path(person)
    assert_match "filed under Health", response.body
  end

  test "unticking every section hands the contact back to the assistant" do
    person = users(:one).people.create!(name: "Dr. Alvarez")
    person.sections << sections(:health)

    assert_enqueued_with(job: CategorizePersonJob) do
      patch person_path(person), params: { person: { name: "Dr. Alvarez", section_ids: [ "" ] } }
    end
    assert_empty person.reload.sections
  end

  test "editing a filed contact leaves their sections alone" do
    person = users(:one).people.create!(name: "Dr. Alvarez")
    person.sections << sections(:health)

    assert_no_enqueued_jobs(only: CategorizePersonJob) do
      patch person_path(person), params: { person: { phone: "+1 555 010 9000", section_ids: [ sections(:health).id ] } }
    end
    assert_equal [ sections(:health) ], person.reload.sections.to_a
  end

  # D-contact-photos: a face for every contact, not only the ones with a login.
  test "uploads and removes a contact photo" do
    person = users(:one).people.create!(name: "Mom")

    patch person_path(person), params: { person: { avatar: contact_photo } }
    assert person.reload.avatar.attached?

    delete person_avatar_path(person)
    assert_redirected_to edit_person_path(person)
    assert_not person.reload.avatar.attached?
  end

  test "a contact photo is only ever your own contact's" do
    other = users(:two).people.create!(name: "Bob's friend")

    delete person_avatar_path(other)
    assert_response :not_found
  end

  test "index shows only visible people" do
    users(:one).people.create!(name: "My Doctor")
    users(:two).people.create!(name: "Bob's Dentist")

    get people_path
    assert_response :success
    assert_match "My Doctor", response.body
    assert_no_match "Bob&#39;s Dentist", response.body
  end

  private
    def contact_photo
      fixture_file_upload("photo.jpg", "image/jpeg")
    end

  # D-people-circles: the circle's full view is the Address Book filtered,
  # not a fourth People surface.
  test "the address book filters to your circle" do
    users(:one).people.create!(name: "Circle Sam", keep_in_touch: true)
    users(:one).people.create!(name: "Rolodex Rex")

    get people_path
    assert_match "Circle Sam", response.body
    assert_match "Rolodex Rex", response.body

    get people_path(circle: "1")
    assert_match "Circle Sam", response.body
    assert_no_match "Rolodex Rex", response.body
  end

  # D-address-book-directory: the roster is the surface that has to survive a
  # CardDAV import, and after one the only thing on it that works is search.
  test "search narrows the roster, and reaches past the name" do
    users(:one).people.create!(name: "Rosa Alvarez", email: "rosa@example.com")
    users(:one).people.create!(name: "Bo Chen", phone: "(555) 867-5309")
    users(:one).people.create!(name: "Dee Ellis", address: "14 Cedar Street")

    get people_path(q: "rosa")
    assert_match "Rosa Alvarez", response.body
    assert_no_match "Bo Chen", response.body

    get people_path(q: "867-5309")
    assert_match "Bo Chen", response.body
    assert_no_match "Rosa Alvarez", response.body

    get people_path(q: "cedar")
    assert_match "Dee Ellis", response.body
    assert_no_match "Bo Chen", response.body
  end

  test "a search that misses offers to add the name you typed" do
    get people_path(q: "Rosa")
    assert_response :success
    assert_select "a[href=?]", new_person_path(name: "Rosa")

    get new_person_path(name: "Rosa")
    assert_select "input[name=?][value=?]", "person[name]", "Rosa"
  end

  test "the roster is alphabetized under letter headings, case be damned" do
    users(:one).people.create!(name: "abby Nguyen")
    users(:one).people.create!(name: "Zoe Park")
    users(:one).people.create!(name: "\u{c774}\u{c900}")

    get people_path
    assert_select "h2#letter-a", "A"
    assert_select "h2#letter-z", "Z"
    assert_select "h2#letter-other", "#",
      "a name that doesn't start with a letter gets a bucket, not the bin"
    assert_operator response.body.index("abby Nguyen"), :<, response.body.index("Zoe Park"),
      "lowercase names sort with their letter, not after Z"
  end

  test "the group filter narrows to a lens, and only groups with people get a chip" do
    club = People::Group.find_or_create!("Book club")
    empty = People::Group.find_or_create!("Ghost town")
    rosa = users(:one).people.create!(name: "Rosa Alvarez")
    rosa.sections << club
    users(:one).people.create!(name: "Bo Chen")

    get people_path
    assert_select "a[href=?]", people_path(group: club.slug)
    assert_select "a[href=?]", people_path(group: empty.slug), false,
      "a chip that leads to an empty page is worse than no chip"

    get people_path(group: club.slug)
    assert_match "Rosa Alvarez", response.body
    assert_no_match "Bo Chen", response.body
  end

  test "a stale group slug shows the address book rather than a 404" do
    users(:one).people.create!(name: "Rosa Alvarez")

    get people_path(group: "a-group-somebody-deleted")
    assert_response :success
    assert_match "Rosa Alvarez", response.body
  end

  test "the row carries the addresses an address book is for" do
    users(:one).people.create!(name: "Rosa Alvarez", email: "rosa@example.com", phone: "555-0100")

    get people_path
    assert_select "a[href=?]", "mailto:rosa@example.com"
    assert_select "a[href=?]", "tel:555-0100"
  end

  # The chip said "People" on every row of a page called People. The groups
  # are the tags that tell two contacts apart; the parent lens never does.
  test "rows chip the groups someone is in, never the People lens itself" do
    rosa = users(:one).people.create!(name: "Rosa Alvarez")
    rosa.sections << People::Group.find_or_create!("Book club")
    rosa.sections << sections(:people)

    get people_path
    assert_select ".item-row a", text: "Book club"
    assert_select ".item-row a", { text: "People", count: 0 },
      "the parent lens is not a distinguishing tag on its own roster"
  end

  test "the circle filter is yours alone, even for shared contacts" do
    theirs = users(:two).people.create!(name: "Shared Sal", keep_in_touch: true)
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: theirs)
    users(:one).people.create!(name: "Circle Sam", keep_in_touch: true)

    get people_path(circle: "1")
    assert_match "Circle Sam", response.body
    assert_no_match "Shared Sal", response.body,
      "you don't tend your spouse's circle (D-people-dashboard)"
  end

  test "the person page offers the groups they could join, and the ones they're in" do
    group = People::Group.find_or_create!("Book club")
    person = users(:one).people.create!(name: "Rosa")

    get person_path(person)
    assert_match "Groups", response.body
    assert_select "form[action=?]", people_memberships_path

    person.sections << group
    get person_path(person)
    assert_select "form[action=?]", people_membership_path(section_id: group.id, person_id: person.id)
  end

  # A pet's lens is a child of People so "about Rex" is a tag
  # (D-pet-primitive), but Rex is not a group of people: the vet made from
  # the pet form was being offered "Add to group → Rex".
  test "a pet's lens is never offered as a group" do
    rex = create_pet(name: "Rex")
    club = People::Group.find_or_create!("Book club")
    vet = users(:one).people.create!(name: "Bethany Family Pet Clinic")

    get person_path(vet)

    assert_select "select[name=section_id] option[value=?]", club.id.to_s
    assert_select "select[name=section_id] option[value=?]", rex.section_id.to_s, false
  end

  test "the address book has no group chip for a pet" do
    rex = create_pet(name: "Rex")
    users(:one).people.create!(name: "Dr. Alvarez").sections << rex.section

    get people_path

    assert_select "a[href=?]", people_path(group: rex.section.slug), false
  end
end
