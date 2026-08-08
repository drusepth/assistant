class SpendingAccountsController < ApplicationController
  def create
    account = Current.user.spending_accounts.new(account_params)
    if account.save
      redirect_back fallback_location: spending_path, notice: "#{account.name} added."
    else
      redirect_back fallback_location: spending_path, alert: account.errors.full_messages.to_sentence
    end
  end

  # Deleting an account purges its slice of the mirror (Spending::Mirror,
  # via the model callback) — the statements in the vault survive, so
  # re-creating the account and re-importing rebuilds everything.
  def destroy
    account = Current.user.spending_accounts.find(params[:id])
    account.destroy!
    redirect_to spending_path, notice: "#{account.name} and its transactions removed from the ledger."
  end

  private
    def account_params
      params.expect(spending_account: %i[ name kind last4 ])
    end
end
