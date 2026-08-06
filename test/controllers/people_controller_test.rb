require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "creates a person linked to a household member" do
    assert_difference("Person.count") do
      post people_path, params: {
        person: { name: "Bob Smith", relationship: "Husband", linked_user_id: users(:two).id, section_ids: [ sections(:health).id ] }
      }
    end
    assert_equal users(:two), Person.last.linked_user
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
