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
end
