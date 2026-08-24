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

  test "turning cloud models off takes the hosted providers out of the picker" do
    assert_equal ModelProfile::PROVIDERS.keys, ModelProfile.selectable_providers(allow_cloud: true)
    assert_equal [ "custom" ], ModelProfile.selectable_providers(allow_cloud: false)

    %w[ openai anthropic google chroma_golem ].each do |provider|
      assert ModelProfile.cloud_provider?(provider), "#{provider} is somebody else's computer"
    end
    assert_not ModelProfile.cloud_provider?("custom"), "a URL you type is not a hosted service"
  end

  test "a cloud provider can't be saved while cloud models are turned off" do
    profile = model_profiles(:smith)

    profile.assign_attributes(provider: "anthropic", model: "claude-opus-5", allow_cloud_models: false)
    assert_not profile.valid?
    assert_match(/cloud models are turned off/, profile.errors.full_messages.to_sentence)

    # The escape hatch is never gated: it's how you reach a local model.
    profile.assign_attributes(provider: "custom", base_url: "http://localhost:11434/v1", model: "llama3.2")
    assert profile.valid?
  end

  test "client refuses a cloud provider the household has turned off" do
    profile = model_profiles(:smith)
    profile.update_column(:allow_cloud_models, false) # only a hand-edited row gets here

    error = assert_raises(Llm::Error) { profile.client }
    assert_match "Cloud models are turned off", error.message

    profile.update_column(:allow_cloud_models, true)
    assert_kind_of Llm::Client, profile.client
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
