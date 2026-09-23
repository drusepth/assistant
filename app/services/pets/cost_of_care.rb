module Pets
  # What the pets actually cost (D-pet-food-shelf, MONEY.md §2). Two numbers
  # from two different places, and the difference between them is the point:
  #
  # - **planned** is the food shelf's arithmetic — what the current diet costs
  #   a month, derived from bags and daily amounts;
  # - **spent** is the ledger's own answer — twelve months of transactions
  #   filed to the pets envelope.
  #
  # The ledger half is honest about what a ledger cannot see: cash, and the
  # grocery trip that also contained a bag of kibble. It says so rather than
  # presenting a confident total, and it says nothing at all when there is no
  # ledger — a "$0 a year" on a pet page is a lie about a dog, not a fact.
  class CostOfCare
    LOOKBACK = 12

    # The envelope pet spending files into. Named once; the offer to create
    # it, the rule button and this lookup all use it.
    CATEGORY_NAME = "Pets".freeze

    def initialize(user)
      @user = user
    end

    attr_reader :user

    # The envelope, if it exists. One lookup, so the card, the create button
    # and the rule form can't disagree about which row they mean.
    def self.category_for(user)
      user.budget_categories.active.find_by("LOWER(name) = ?", CATEGORY_NAME.downcase)
    end

    def category = @category ||= self.class.category_for(user)

    def ledger? = SpendingTransaction.where(user_id: user.id).exists?

    # Whether the card has anything to say. Without a ledger there is no
    # spending to report and no shop to teach a rule for, so the card would
    # be an empty box; with one, it carries either the number or the rule
    # form that files the next Chewy order where this card can see it.
    def any? = category.present? && ledger?

    def transactions
      return SpendingTransaction.none if category.nil?

      SpendingTransaction.where(user_id: user.id, budget_category_id: category.id)
        .spending.where(occurred_on: LOOKBACK.months.ago.to_date..)
    end

    # Unsigned cents over the window, or nil when there's nothing honest to
    # report yet.
    def spent_cents
      return nil if category.nil? || !ledger?

      total = transactions.sum(:amount_cents)
      total.zero? ? nil : total.abs
    end

    def monthly_average_cents
      spent = spent_cents
      spent && (spent / LOOKBACK.to_f).round
    end
  end
end
