require "test_helper"

# M4.1: the FTUE gate and four-step flow, plus api_key encryption at rest.
class OnboardingFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      household: households(:smith), name: "New Member",
      email_address: "new@example.com", password: "password", admin: true
    )
    post session_path, params: { email_address: "new@example.com", password: "password" }
  end

  test "an un-onboarded user is routed to the welcome flow, and reaching the last step completes it" do
    get root_path
    assert_redirected_to onboarding_path(step: 1)

    get onboarding_path(step: 1)
    assert_response :success
    assert_match "What parts of life", response.body

    patch onboarding_path(step: 1), params: { enabled_section_ids: [ sections(:health).id, sections(:money).id ] }
    assert_redirected_to onboarding_path(step: 2)
    assert @user.section_enabled?(sections(:health))
    assert_not @user.reload.section_enabled?(sections(:career))

    patch onboarding_path(step: 2), params: { agent_voice: "off" }
    assert_equal "off", @user.agent_level_for(sections(:health))

    get onboarding_path(step: 4)
    assert_not_nil @user.reload.onboarded_at

    get root_path
    assert_response :success
  end

  test "non-admins skip the model step" do
    @user.update!(admin: false)

    get onboarding_path(step: 3)
    assert_match "Bring your life in", response.body, "step 3 renders as step 4 for members"
  end

  test "onboarded users never see the gate; sign-out works before onboarding" do
    sign_in_as users(:one)
    get root_path
    assert_response :success

    delete session_path
    assert_redirected_to new_session_path
  end

  test "api keys are encrypted at rest" do
    profile = model_profiles(:smith)
    profile.update!(api_key: "sk-super-secret")

    raw = ModelProfile.connection.select_value(
      "SELECT api_key FROM model_profiles WHERE id = #{profile.id}"
    )
    assert_not_equal "sk-super-secret", raw, "the raw column must not hold plaintext"
    assert_equal "sk-super-secret", profile.reload.api_key
  end

  # A pet is the one household member no import can teach the app about, so
  # the last step offers one — as a fourth shortcut, not as a fifth step and
  # not as a question on step 1, where a pet is not a section.
  test "the last step offers a pet, and stops once the household has one" do
    get onboarding_path(step: 4)
    assert_select "a[href=?]", new_pet_path

    create_pet(user: users(:one))
    users(:one).granted_access_grants.create!(grantee: @user, subject: Pet.sole)

    get onboarding_path(step: 4)
    assert_select "a[href=?]", new_pet_path, { count: 0 },
      "the second member to onboard is not asked to add the dog again"
  end

  test "a pet somebody kept private still leaves the offer up" do
    create_pet(user: users(:one))

    get onboarding_path(step: 4)
    assert_select "a[href=?]", new_pet_path, { minimum: 1 },
      "visibility is the only read path — an unshared pet is not one this user has"
  end
end
