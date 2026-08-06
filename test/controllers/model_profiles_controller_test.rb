require "test_helper"

class ModelProfilesControllerTest < ActionDispatch::IntegrationTest
  test "an admin updates the household model settings" do
    sign_in_as users(:one)

    patch model_profile_path, params: {
      model_profile: { provider: "custom", base_url: "http://localhost:11434/v1", model: "llama3.2", api_key: "new-key" }
    }
    assert_redirected_to settings_path

    profile = households(:smith).reload.model_profile
    assert_equal "custom", profile.provider
    assert_equal "http://localhost:11434/v1", profile.base_url
    assert_equal "llama3.2", profile.model
    assert_equal "new-key", profile.api_key
  end

  test "switching to chroma golem needs only a key" do
    sign_in_as users(:one)

    patch model_profile_path, params: {
      model_profile: { provider: "chroma_golem", base_url: "", model: "", api_key: "cg-credits" }
    }
    assert_redirected_to settings_path

    profile = households(:smith).reload.model_profile
    assert_equal "chroma_golem", profile.provider
    assert profile.configured?
    assert_equal "https://api.chromagolem.com/v1", profile.effective_base_url
  end

  test "a blank api key keeps the stored one" do
    sign_in_as users(:one)

    patch model_profile_path, params: { model_profile: { base_url: "https://api.openai.com/v1", model: "gpt-4o", api_key: "" } }

    profile = households(:smith).reload.model_profile
    assert_equal "test-key", profile.api_key
    assert_equal "gpt-4o", profile.model
  end

  test "non-admins cannot change model settings" do
    sign_in_as users(:two)

    patch model_profile_path, params: { model_profile: { base_url: "https://evil.example", model: "x", api_key: "y" } }
    assert_redirected_to settings_path
    assert_equal "https://api.openai.com/v1", households(:smith).reload.model_profile.base_url
  end

  test "creates the profile on first save for a household without one" do
    sign_in_as users(:outsider)
    users(:outsider).update!(admin: true)

    assert_difference("ModelProfile.count") do
      patch model_profile_path, params: { model_profile: { base_url: "https://api.openai.com/v1", model: "gpt-4o-mini", api_key: "k" } }
    end
    assert_equal households(:jones), ModelProfile.last.household
  end
end
