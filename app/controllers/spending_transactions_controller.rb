# Ledger row actions: quick-log (create), recategorize / transfer toggle
# (update), remove-from-mirror (destroy). Owner-scoped by construction —
# every lookup starts from Current.user's id (D-mirror-layer).
class SpendingTransactionsController < ApplicationController
  before_action :set_transaction, only: %i[ update destroy ]

  def create
    row = Spending::QuickLog.call(user: Current.user, text: params[:entry])
    if row
      redirect_back fallback_location: spending_path,
        notice: "Logged #{helpers.money_amount(row.amount_cents)} — #{row.display_merchant}."
    else
      redirect_back fallback_location: spending_path,
        alert: "Couldn't read that — try an amount then a description, like “14.50 lunch”."
    end
  end

  def update
    if params.key?(:transfer)
      # The user's word on what's a transfer is final: auto-pairing never
      # touches a row a human toggled (Spending::Transfers).
      @transaction.update!(transfer: params[:transfer] == "1", transfer_set_by: "user")
      return redirect_back fallback_location: spending_path
    end

    category = find_category
    @transaction.recategorize!(category)

    if category && params[:make_rule] == "1" && @transaction.merchant.present?
      rule = Current.user.spending_rules.create_with(budget_category: category)
        .find_or_create_by(matcher: @transaction.merchant.downcase)
      rule.update!(budget_category: category) unless rule.budget_category_id == category.id
      Spending::Categorize.new(user: Current.user).apply_rule(rule)
    end

    redirect_back fallback_location: spending_path
  end

  def destroy
    @transaction.remove_from_mirror!
    redirect_back fallback_location: spending_path,
      notice: "Removed from the ledger for good — re-importing the same statement won't bring it back."
  end

  private
    def set_transaction
      @transaction = SpendingTransaction.where(user_id: Current.user.id).find(params[:id])
    end

    def find_category
      return nil if params[:budget_category_id].blank?
      Current.user.budget_categories.find(params[:budget_category_id])
    end
end
