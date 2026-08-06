require "test_helper"

class FirstRunControllerTest < ActionDispatch::IntegrationTest
  test "setup is locked once any user exists" do
    get setup_path
    assert_redirected_to new_session_path

    post setup_path, params: { user: { name: "Mallory", email_address: "mallory@example.com", password: "password123" } }
    assert_redirected_to new_session_path
  end

  test "fresh instance onboards the first user as household admin" do
    empty_the_instance

    get new_session_path
    assert_redirected_to setup_path

    get setup_path
    assert_response :success

    assert_difference [ "Household.count", "User.count" ], 1 do
      post setup_path, params: {
        household_name: "The Riveras",
        user: { name: "Alice Rivera", email_address: "alice@rivera.example", password: "password123" }
      }
    end
    assert_redirected_to root_path

    user = User.last
    assert user.admin?
    assert_equal "The Riveras", user.household.name

    follow_redirect!
    assert_redirected_to onboarding_path(step: 1), "a fresh admin starts in the welcome flow (Q5)"
    follow_redirect!
    assert_match "What parts of life", response.body
  end

  test "household name defaults from the first name" do
    empty_the_instance
    post setup_path, params: { user: { name: "Alice Rivera", email_address: "alice@rivera.example", password: "password123" } }
    assert_equal "Alice's Household", Household.last.name
  end

  test "re-renders with errors on invalid input" do
    empty_the_instance
    assert_no_difference "User.count" do
      post setup_path, params: { user: { name: "", email_address: "alice@rivera.example", password: "password123" } }
    end
    assert_response :unprocessable_entity
  end

  private
    def empty_the_instance
      [ Invitation, ModelProfile, AccessGrant, Session, UserSection, SectionTagging,
        Task, Event, Document, Person, Note, Goal, User, Household ].each(&:delete_all)
    end
end
