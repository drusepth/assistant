module Health
  # Insurance lives in the vault as ordinary Documents (Q3: coverage and
  # care navigation belong to Health; billing disputes stay in Rights).
  # This finds the plan-shaped ones — insurance cards, Summaries of
  # Benefits, EOBs — by keyword over title and AI summary, a heuristic the
  # Health page's coverage card and the find-care tool share. Visible
  # documents, not just owned: coverage is often a household fact, and a
  # spouse's shared plan document is exactly what these tools should read.
  class Coverage
    PATTERNS = [
      /insurance/i, /summary of benefits/i, /\bsbc\b/i, /explanation of benefits/i, /\beob\b/i,
      /medicaid/i, /medicare/i, /co-?pay/i, /deductible/i, /formulary/i,
      /health plan/i, /\bhmo\b/i, /\bppo\b/i, /\bepo\b/i, /\bhdhp\b/i
    ].freeze

    # Pinned plans (health_plan: true) lead; within a group, newest first.
    def self.documents(user, limit: 5)
      Document.visible_to(user).order(created_at: :desc).includes(:sections, :user)
        .select { |document| match?(document) }
        .sort_by { |document| [ document.health_plan ? 0 : 1, -document.created_at.to_i ] }
        .first(limit)
    end

    # The owner's word beats the keywords (docs/HEALTH.md §4): health_plan
    # true pins a document here, false banishes it, nil means the heuristic
    # decides.
    def self.match?(document)
      return document.health_plan unless document.health_plan.nil?

      haystack = [ document.title, document.summary ].compact.join("\n")
      PATTERNS.any? { |pattern| haystack.match?(pattern) }
    end
  end
end
