# Rules are visible, removable configuration (D9) — created by one-click
# "always file here" while recategorizing, deleted here. Removing a rule
# leaves rows it already filed alone; it just stops deciding the future.
class SpendingRulesController < ApplicationController
  def destroy
    rule = Current.user.spending_rules.find(params[:id])
    rule.destroy!
    redirect_back fallback_location: spending_path, notice: "Rule for “#{rule.matcher}” removed."
  end
end
