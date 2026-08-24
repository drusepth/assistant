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

  test "switching to Anthropic or Google needs only a key and a model name" do
    sign_in_as users(:one)

    patch model_profile_path, params: {
      model_profile: { provider: "anthropic", base_url: "", model: "claude-opus-5", api_key: "sk-ant-key" }
    }
    assert_redirected_to settings_path

    profile = households(:smith).reload.model_profile
    assert_equal "anthropic", profile.provider
    assert profile.configured?
    assert_equal "https://api.anthropic.com/v1", profile.effective_base_url

    patch model_profile_path, params: {
      model_profile: { provider: "google", base_url: "", model: "gemini-3.7-flash", api_key: "goog-key" }
    }

    profile = households(:smith).reload.model_profile
    assert_equal "google", profile.provider
    assert_equal "https://generativelanguage.googleapis.com/v1beta/openai", profile.effective_base_url
  end

  test "cloud models can be turned off, and the picker's local option still saves" do
    sign_in_as users(:one)

    patch model_profile_path, params: {
      model_profile: { provider: "custom", base_url: "http://localhost:11434/v1", model: "llama3.2",
                       api_key: "", allow_cloud_models: "0" }
    }
    assert_redirected_to settings_path

    profile = households(:smith).reload.model_profile
    assert_not profile.allow_cloud_models?
    assert_equal "custom", profile.provider
  end

  test "a cloud provider is refused while cloud models are off, and the old settings stand" do
    sign_in_as users(:one)
    households(:smith).model_profile.update!(allow_cloud_models: false, provider: "custom",
      base_url: "http://localhost:11434/v1", model: "llama3.2")

    patch model_profile_path, params: {
      model_profile: { provider: "openai", model: "gpt-4o-mini", api_key: "sk-x", allow_cloud_models: "0" }
    }
    assert_redirected_to settings_path
    assert_match(/cloud models are turned off/, flash[:alert])

    profile = households(:smith).reload.model_profile
    assert_equal "custom", profile.provider, "the rejected save changed nothing"
  end

  test "a blank api key keeps the stored one" do
    sign_in_as users(:one)

    patch model_profile_path, params: { model_profile: { base_url: "https://api.openai.com/v1", model: "gpt-4o", api_key: "" } }

    profile = households(:smith).reload.model_profile
    assert_equal "test-key", profile.api_key
    assert_equal "gpt-4o", profile.model
  end

  test "the web-capable flag saves and clears" do
    sign_in_as users(:one)

    patch model_profile_path, params: {
      model_profile: { provider: "openai", model: "gpt-4o-mini", api_key: "k", web_capable: "1" }
    }
    assert households(:smith).reload.model_profile.web_capable?

    patch model_profile_path, params: {
      model_profile: { provider: "openai", model: "gpt-4o-mini", api_key: "", web_capable: "0" }
    }
    assert_not households(:smith).reload.model_profile.web_capable?
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
