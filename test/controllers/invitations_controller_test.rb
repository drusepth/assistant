require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  test "an admin creates and revokes an invitation" do
    sign_in_as users(:one)

    assert_difference("Invitation.count") do
      post invitations_path, params: { invitation: { name: "Grandma June" } }
    end
    assert_redirected_to settings_path

    invitation = Invitation.last
    assert_equal households(:smith), invitation.household

    assert_difference("Invitation.count", -1) { delete invitation_path(invitation) }
  end

  test "non-admins cannot invite" do
    sign_in_as users(:two)
    assert_no_difference("Invitation.count") do
      post invitations_path, params: { invitation: { name: "Someone" } }
    end
    assert_redirected_to settings_path
  end

  test "a valid link joins the household" do
    invitation = households(:smith).invitations.create!(inviter: users(:one), name: "Grandma June")
    token = invitation.join_token

    get join_path(token)
    assert_response :success
    assert_match "Join Smith Household", response.body
    assert_match "Grandma June", response.body

    assert_difference("User.count") do
      post join_path(token), params: {
        user: { name: "June Smith", email_address: "june@example.com", password: "password123" }
      }
    end
    assert_redirected_to root_path

    june = User.find_by(email_address: "june@example.com")
    assert_equal households(:smith), june.household
    assert_not june.admin?
    assert invitation.reload.accepted?
  end

  test "an accepted link cannot be reused" do
    invitation = households(:smith).invitations.create!(inviter: users(:one), name: "June")
    token = invitation.join_token
    post join_path(token), params: { user: { name: "June", email_address: "june@example.com", password: "password123" } }
    delete session_path

    get join_path(token)
    assert_redirected_to new_session_path
    assert_no_difference("User.count") do
      post join_path(token), params: { user: { name: "Evil", email_address: "evil@example.com", password: "password123" } }
    end
  end

  test "revoked and expired links are rejected" do
    invitation = households(:smith).invitations.create!(inviter: users(:one), name: "June")
    token = invitation.join_token
    invitation.destroy!
    get join_path(token)
    assert_redirected_to new_session_path

    fresh = households(:smith).invitations.create!(inviter: users(:one), name: "June")
    stale_token = fresh.join_token
    travel 8.days do
      get join_path(stale_token)
      assert_redirected_to new_session_path
    end
  end

  test "invalid input re-renders the join form" do
    invitation = households(:smith).invitations.create!(inviter: users(:one), name: "June")
    post join_path(invitation.join_token), params: {
      user: { name: "June", email_address: users(:one).email_address, password: "password123" }
    }
    assert_response :unprocessable_entity
    assert_not invitation.reload.accepted?
  end

  test "signed-in users are bounced off join links" do
    sign_in_as users(:one)
    invitation = households(:smith).invitations.create!(inviter: users(:one), name: "June")
    get join_path(invitation.join_token)
    assert_redirected_to root_path
  end
end
