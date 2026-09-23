module Health
  # Insurance lives in the vault as ordinary Documents (Q3: coverage and
  # care navigation belong to Health; billing disputes stay in Rights).
  # This finds the plan-shaped ones — insurance cards, Summaries of
  # Benefits, EOBs — a heuristic the Health page's coverage card and the
  # find-care tool share. Visible documents, not just owned: coverage is
  # often a household fact, and a spouse's shared plan document is exactly
  # what these tools should read.
  #
  # Three voices can answer "is this insurance?", and the first one that
  # has spoken decides: the owner (`documents.health_plan` — only ever set
  # by a person), then the reader (`extracted_facts["health_plan"]`, the
  # model's verdict at analysis time, replaced on every re-read —
  # D-document-intake), then the keyword patterns below, which therefore
  # only ever see documents no model has read: the D-no-keyword-logic
  # cleanup, taken as far as an instance without a model allows.
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

    def self.match?(document) = verdict(document).first

    # [answer, who gave it] — who is :owner, :reader or :keywords, so the
    # document page can say whose answer it is showing (docs/HEALTH.md §4).
    def self.verdict(document)
      return [ document.health_plan, :owner ] unless document.health_plan.nil?

      automatic_verdict(document)
    end

    # What the document would count as if its owner hadn't answered — the
    # "decide from what it says" choice on the edit form shows it.
    def self.automatic_verdict(document)
      read = document.extracted_facts["health_plan"]
      return [ read, :reader ] if read == true || read == false

      haystack = [ document.title, document.summary ].compact.join("\n")
      [ PATTERNS.any? { |pattern| haystack.match?(pattern) }, :keywords ]
    end
  end
end
