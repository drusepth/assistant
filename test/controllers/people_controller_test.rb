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

  test "index shows only visible people" do
    users(:one).people.create!(name: "My Doctor")
    users(:two).people.create!(name: "Bob's Dentist")

    get people_path
    assert_response :success
    assert_match "My Doctor", response.body
    assert_no_match "Bob&#39;s Dentist", response.body
  end
end
