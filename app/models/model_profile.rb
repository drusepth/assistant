# Household-level model configuration (D10). One profile per household,
# managed by admins from Settings. Providers are presets over the same
# OpenAI-compatible adapter — "custom" exposes the raw base_url for anything
# the household runs or picks itself (Ollama, llama.cpp, LM Studio, and also
# OpenRouter or Groq). api_key is encrypted at rest (D14).
#
# allow_cloud_models is the household's standing answer to "may this app talk
# to someone else's computer at all" (D-local-first-models): on by default,
# and turning it off takes every hosted provider out of the picker.
class ModelProfile < ApplicationRecord
  # Every preset is the same OpenAI-compatible adapter pointed somewhere else.
  # Anthropic and Google both publish an OpenAI-compatible chat-completions
  # endpoint that takes a plain API key on the Authorization header, so both
  # are a base_url away — no vendor gem, no extra setup for the household.
  #
  # Per-provider keys beyond the URL:
  #   :model_required — false for router-style providers that pick server-side
  #   :json_mode      — :response_format (the OpenAI field) or :prompt, for
  #                     providers that silently ignore response_format
  #   :max_tokens     — sent when the provider requires an output cap
  #   :suggested_model — pre-filled in the settings form; free text, editable
  #   :cloud          — true for somebody else's computer, billed per token.
  #                     Gated behind allow_cloud_models; a preset without it
  #                     is one the household runs or aims itself, and stays
  #                     in the picker whatever the toggle says. A first-class
  #                     local preset lands here later with :cloud simply
  #                     absent (D-local-first-models).
  PROVIDERS = {
    "openai" => { label: "OpenAI", base_url: "https://api.openai.com/v1", model_required: true,
                  suggested_model: "gpt-4o-mini", cloud: true },
    # Anthropic's OpenAI-compatibility layer lives on the normal API host and
    # accepts a Claude API key as a bearer token. Two quirks we work around:
    # it ignores response_format (so JSON is asked for in the prompt instead),
    # and the underlying Messages API wants an output cap on every request.
    "anthropic" => { label: "Anthropic (Claude)", base_url: "https://api.anthropic.com/v1", model_required: true,
                     json_mode: :prompt, max_tokens: 8192, suggested_model: "claude-opus-5", cloud: true },
    # Gemini's OpenAI-compatible endpoint: same bearer-token API key from
    # Google AI Studio, and response_format works, so nothing to special-case.
    "google" => { label: "Google (Gemini)", base_url: "https://generativelanguage.googleapis.com/v1beta/openai",
                  model_required: true, suggested_model: "gemini-3.7-flash", cloud: true },
    # Chroma Golem is a router: one key, and the model is chosen on their
    # website — so no model name here. client_id is their per-end-user
    # attribution parameter; we send an opaque household id.
    "chroma_golem" => { label: "Chroma Golem", base_url: "https://api.chromagolem.com/v1", model_required: false,
                        cloud: true },
    # The only preset that can already point at a model on your own machine:
    # Ollama, llama.cpp and LM Studio all serve this wire format. It is also
    # how you reach OpenRouter or Groq, which is exactly why it is not gated —
    # the app can't know where a URL you typed goes, and says so rather than
    # pretending the toggle is a firewall.
    "custom" => { label: "Local or self-hosted endpoint", base_url: nil, model_required: true }
  }.freeze

  # Providers whose model name the settings form pre-fills, so switching the
  # picker can swap one suggestion for another without clobbering a name the
  # household typed themselves.
  SUGGESTED_MODELS = PROVIDERS.filter_map { |key, settings| [ key, settings[:suggested_model] ] if settings[:suggested_model] }.to_h.freeze

  # Somebody else's computer, billed per token — the set allow_cloud_models
  # gates.
  CLOUD_PROVIDERS = PROVIDERS.select { |_key, settings| settings[:cloud] }.keys.freeze
  SELF_RUN_PROVIDERS = (PROVIDERS.keys - CLOUD_PROVIDERS).freeze

  # What the picker may offer. Reads the flag rather than a profile so the
  # settings form can call it for a household that has never saved one.
  def self.selectable_providers(allow_cloud: true)
    allow_cloud ? PROVIDERS.keys : SELF_RUN_PROVIDERS
  end

  def self.cloud_provider?(provider) = CLOUD_PROVIDERS.include?(provider.to_s)

  belongs_to :household

  # At-rest encryption (D14 leftover, closed in M4.1). Keys are generated
  # per-instance on first boot — see config/initializers/active_record_encryption.rb.
  encrypts :api_key

  validates :provider, inclusion: { in: PROVIDERS.keys }
  validates :model, presence: true, if: :model_required?
  validates :base_url, presence: true, if: -> { provider == "custom" }
  validates :household_id, uniqueness: true
  validate :cloud_provider_is_allowed

  def configured? = api_key.present?

  # Unknown providers fail the inclusion validation; fall back so the other
  # validations can still run without raising.
  def provider_settings = PROVIDERS.fetch(provider) { { label: provider, base_url: nil, model_required: true } }
  def model_required? = provider_settings[:model_required]
  def cloud? = self.class.cloud_provider?(provider)

  def effective_base_url
    provider_settings[:base_url] || base_url
  end

  def display_name
    case provider
    when "openai" then "OpenAI (#{model})"
    when "anthropic" then "Anthropic (#{model})"
    when "google" then "Google (#{model})"
    when "chroma_golem" then "Chroma Golem"
    else "#{model} at #{endpoint_host}"
    end
  end

  # A custom base_url is free text, so it can be unparseable — and this is
  # read on the dashboard, where raising would take the whole page down over
  # a cosmetic label. Fall back to showing the raw value.
  def endpoint_host
    URI(effective_base_url.to_s).host.presence || effective_base_url
  rescue URI::InvalidURIError
    effective_base_url
  end

  def client
    # The validation below keeps this pair coherent through the app; this is
    # the backstop for a row that got here another way (a hand-edited
    # database, a restored backup). Refusing beats quietly calling a provider
    # the household has said no to.
    raise Llm::Error, "Cloud models are turned off for this household." if cloud? && !allow_cloud_models?

    Llm::Client.new(
      base_url: effective_base_url,
      api_key: api_key,
      model: model.presence,
      extra_params: extra_params,
      json_mode: provider_settings.fetch(:json_mode, :response_format),
      max_tokens: provider_settings[:max_tokens]
    )
  end

  private
    def extra_params
      provider == "chroma_golem" ? { client_id: "household_#{household_id}" } : {}
    end

    def cloud_provider_is_allowed
      return unless cloud? && !allow_cloud_models?

      errors.add(:provider,
        "#{provider_settings[:label]} is a cloud provider, and cloud models are turned off. " \
        "Point the app at a model you run, or allow cloud models again.")
    end
end
