# Household-level model configuration (D10). One profile per household for
# now; defaults point at OpenAI, but any OpenAI-compatible endpoint works
# (Ollama, OpenRouter, Groq, …) by changing base_url. Per-task routing and
# multiple profiles can come later. api_key is plaintext for now — encryption
# hardening is deliberately deferred (D10).
class ModelProfile < ApplicationRecord
  belongs_to :household

  validates :base_url, :model, presence: true
  validates :household_id, uniqueness: true

  def configured? = api_key.present?

  def client
    Llm::Client.new(base_url: base_url, api_key: api_key, model: model)
  end
end
