class AddWebCapableToModelProfiles < ActiveRecord::Migration[8.1]
  def change
    # D-career-web: the admin's declaration that the configured provider can browse
    # the web itself (OpenRouter :online, Perplexity-style). Prompts relax
    # their never-assert-current-facts guardrails only when this is on.
    add_column :model_profiles, :web_capable, :boolean, default: false, null: false
  end
end
