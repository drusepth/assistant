require "test_helper"

class ModelProfileTest < ActiveSupport::TestCase
  test "openai and custom providers require a model; chroma golem does not" do
    profile = model_profiles(:smith)

    profile.model = nil
    assert_not profile.valid?

    profile.provider = "chroma_golem"
    assert profile.valid?

    profile.provider = "custom"
    profile.base_url = "http://localhost:11434/v1"
    assert_not profile.valid?
  end

  test "custom provider requires a base url; presets ignore it" do
    profile = model_profiles(:smith)
    profile.provider = "custom"
    profile.base_url = nil
    assert_not profile.valid?

    profile.provider = "chroma_golem"
    assert profile.valid?
    assert_equal "https://api.chromagolem.com/v1", profile.effective_base_url
  end

  test "unknown providers are rejected" do
    profile = model_profiles(:smith)
    profile.provider = "skynet"
    assert_not profile.valid?
  end

  test "display_name reads naturally per provider" do
    profile = model_profiles(:smith)
    assert_equal "OpenAI (gpt-4o-mini)", profile.display_name

    profile.provider = "chroma_golem"
    assert_equal "Chroma Golem", profile.display_name

    profile.assign_attributes(provider: "custom", base_url: "http://localhost:11434/v1", model: "llama3.2")
    assert_equal "llama3.2 at localhost", profile.display_name
  end
end
