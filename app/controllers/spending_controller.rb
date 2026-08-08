# The ledger browser (MONEY.md §2.5): the owner-only view of mirrored
# spending — the /mail idiom for money. Strictly owner-scoped: there is
# no visible_to path to the mirror (D-mirror-layer), so every query here
# starts from Current.user's id.
class SpendingController < ApplicationController
  ROW_LIMIT = 500

  def index
    @accounts = Current.user.spending_accounts.order(:created_at)
    @categories = Current.user.budget_categories.active.ordered
    @rules = Current.user.spending_rules.includes(:budget_category).order(:matcher)

    scope = SpendingTransaction.where(user_id: Current.user.id)

    if params[:account].present? && @accounts.map(&:id).include?(params[:account].to_i)
      scope = scope.where(spending_account_id: params[:account].to_i)
    end

    @month = parse_month(params[:month])
    scope = scope.in_month(@month) if @month

    case params[:category]
    when "none" then scope = scope.uncategorized
    when /\A\d+\z/ then scope = scope.where(budget_category_id: params[:category].to_i)
    end

    @query = params[:q].to_s.strip
    if @query.present?
      like = "%#{SpendingTransaction.sanitize_sql_like(@query)}%"
      scope = scope.where("merchant LIKE ? OR descriptor LIKE ?", like, like)
    end

    @transactions = scope.newest_first.limit(ROW_LIMIT).to_a
    @uncategorized_count = SpendingTransaction.where(user_id: Current.user.id).uncategorized.count
    @total_count = SpendingTransaction.where(user_id: Current.user.id).count
    @months = month_choices
  end

  private
    def parse_month(raw)
      Date.strptime(raw.to_s, "%Y-%m")
    rescue Date::Error
      nil
    end

    # The months the ledger actually spans, newest first, for the filter.
    def month_choices
      bounds = SpendingTransaction.where(user_id: Current.user.id)
        .pick(Arel.sql("MIN(occurred_on), MAX(occurred_on)"))
      first, last = bounds
      return [] unless first && last

      months = []
      cursor = last.to_date.beginning_of_month
      while cursor >= first.to_date.beginning_of_month && months.size < 24
        months << cursor
        cursor = cursor.prev_month
      end
      months
    end
end
