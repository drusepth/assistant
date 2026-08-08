# The model garnish on the categorization pipeline (MONEY.md §2.4) —
# batched, behind rules and keywords, best-effort: no model or a failed
# call leaves rows honestly uncategorized, quiet for the user and logged
# for the operator (D23).
class Spending::CategorizeJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(user)
    profile = user.household.model_profile
    return unless profile&.configured?

    Spending::Categorize.new(user: user).classify_with_model(profile)
  rescue Llm::Error => e
    raise if will_retry?(e)

    record_failure(e, user: user)
  end
end
