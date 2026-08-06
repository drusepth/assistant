require "test_helper"

class HouseholdMembersControllerTest < ActionDispatch::IntegrationTest
  test "an admin promotes and demotes another member" do
    sign_in_as users(:one)

    patch household_member_path(users(:two), admin: true)
    assert users(:two).reload.admin?

    patch household_member_path(users(:two), admin: false)
    assert_not users(:two).reload.admin?
  end

  test "an admin removes a member and their data" do
    users(:two).tasks.create!(title: "Bob's task")
    sign_in_as users(:one)

    assert_difference("User.count", -1) do
      delete household_member_path(users(:two))
    end
    assert_not Task.exists?(title: "Bob's task")
  end

  test "removing a member keeps contacts that linked to their account" do
    contact = users(:one).people.create!(name: "Bob Smith", linked_user: users(:two))
    sign_in_as users(:one)

    delete household_member_path(users(:two))
    assert_nil contact.reload.linked_user_id
  end

  test "admins cannot act on themselves" do
    sign_in_as users(:one)

    patch household_member_path(users(:one), admin: false)
    assert users(:one).reload.admin?

    assert_no_difference("User.count") { delete household_member_path(users(:one)) }
  end

  test "non-admins cannot manage members" do
    sign_in_as users(:two)

    patch household_member_path(users(:one), admin: false)
    assert users(:one).reload.admin?

    assert_no_difference("User.count") { delete household_member_path(users(:one)) }
  end

  test "cannot manage members of other households" do
    sign_in_as users(:one)
    patch household_member_path(users(:outsider), admin: true)
    assert_response :not_found
  end
end
