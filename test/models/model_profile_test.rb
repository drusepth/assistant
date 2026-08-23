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

  test "anthropic and google are key-plus-model presets over their own base urls" do
    profile = model_profiles(:smith)

    profile.assign_attributes(provider: "anthropic", model: "claude-opus-5", base_url: nil)
    assert profile.valid?
    assert_equal "https://api.anthropic.com/v1", profile.effective_base_url

    profile.model = nil
    assert_not profile.valid?, "anthropic needs a model name"

    profile.assign_attributes(provider: "google", model: "gemini-3.7-flash")
    assert profile.valid?
    assert_equal "https://generativelanguage.googleapis.com/v1beta/openai", profile.effective_base_url

    profile.model = nil
    assert_not profile.valid?, "google needs a model name"
  end

  test "anthropic carries the quirks its compatibility endpoint needs; other presets do not" do
    profile = model_profiles(:smith)

    profile.assign_attributes(provider: "anthropic", model: "claude-opus-5")
    settings = profile.provider_settings
    assert_equal :prompt, settings[:json_mode], "anthropic ignores response_format"
    assert settings[:max_tokens].present?, "anthropic requires an output cap"

    %w[ openai google chroma_golem custom ].each do |provider|
      preset = ModelProfile::PROVIDERS.fetch(provider)
      assert_nil preset[:json_mode], "#{provider} should use response_format"
      assert_nil preset[:max_tokens], "#{provider} should not force an output cap"
    end
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

    profile.assign_attributes(provider: "anthropic", model: "claude-opus-5")
    assert_equal "Anthropic (claude-opus-5)", profile.display_name

    profile.assign_attributes(provider: "google", model: "gemini-3.7-flash")
    assert_equal "Google (gemini-3.7-flash)", profile.display_name

    profile.assign_attributes(provider: "custom", base_url: "http://localhost:11434/v1", model: "llama3.2")
    assert_equal "llama3.2 at localhost", profile.display_name
  end
end
