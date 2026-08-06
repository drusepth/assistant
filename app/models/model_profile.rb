# Household-level model configuration (D10). One profile per household,
# managed by admins from Settings. Providers are presets over the same
# OpenAI-compatible adapter — "custom" exposes the raw base_url for anything
# else (Ollama, OpenRouter, Groq, llama.cpp). api_key is plaintext for now —
# encryption hardening is deliberately deferred (D10).
class ModelProfile < ApplicationRecord
  PROVIDERS = {
    "openai" => { label: "OpenAI", base_url: "https://api.openai.com/v1", model_required: true },
    # Chroma Golem is a router: one key, and the model is chosen on their
    # website — so no model name here. client_id is their per-end-user
    # attribution parameter; we send an opaque household id.
    "chroma_golem" => { label: "Chroma Golem", base_url: "https://api.chromagolem.com/v1", model_required: false },
    "custom" => { label: "Custom endpoint", base_url: nil, model_required: true }
  }.freeze

  belongs_to :household

  # At-rest encryption (D14 leftover, closed in M4.1). Keys are generated
  # per-instance on first boot — see config/initializers/active_record_encryption.rb.
  encrypts :api_key

  validates :provider, inclusion: { in: PROVIDERS.keys }
  validates :model, presence: true, if: :model_required?
  validates :base_url, presence: true, if: -> { provider == "custom" }
  validates :household_id, uniqueness: true

  def configured? = api_key.present?

  # Unknown providers fail the inclusion validation; fall back so the other
  # validations can still run without raising.
  def provider_settings = PROVIDERS.fetch(provider) { { label: provider, base_url: nil, model_required: true } }
  def model_required? = provider_settings[:model_required]

  def effective_base_url
    provider_settings[:base_url] || base_url
  end

  def display_name
    case provider
    when "openai" then "OpenAI (#{model})"
    when "chroma_golem" then "Chroma Golem"
    else "#{model} at #{URI(effective_base_url).host}"
    end
  end

  def client
    Llm::Client.new(
      base_url: effective_base_url,
      api_key: api_key,
      model: model.presence,
      extra_params: extra_params
    )
  end

  private
    def extra_params
      provider == "chroma_golem" ? { client_id: "household_#{household_id}" } : {}
    end
end
