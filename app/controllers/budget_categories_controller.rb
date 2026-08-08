# Envelope CRUD (D-budget-envelopes). A target the user types here is
# hand-set (`target_set_by: "user"`) — build_my_budget's suggest-and-apply
# can never overwrite it afterwards. Removal archives once a category has
# filed history (rows keep their soft id and the name keeps meaning in
# past months); a never-used envelope just deletes.
class BudgetCategoriesController < ApplicationController
  def create
    # Re-adding an archived envelope's name revives it, history intact.
    if (archived = Current.user.budget_categories.where.not(archived_at: nil)
          .find_by("LOWER(name) = ?", params[:name].to_s.downcase.strip))
      archived.update!(archived_at: nil, group: permitted_group,
        monthly_target_cents: cents_param || archived.monthly_target_cents,
        target_set_by: cents_param ? "user" : archived.target_set_by)
      return redirect_back fallback_location: section_path("budget"), notice: "#{archived.name} is back."
    end

    category = Current.user.budget_categories.new(
      name: params[:name], group: permitted_group,
      monthly_target_cents: cents_param, target_set_by: cents_param ? "user" : nil)

    if category.save
      redirect_back fallback_location: section_path("budget"), notice: "#{category.name} added."
    else
      redirect_back fallback_location: section_path("budget"), alert: category.errors.full_messages.to_sentence
    end
  end

  def update
    category = Current.user.budget_categories.find(params[:id])
    updates = {}
    updates[:name] = params[:name] if params[:name].present?
    updates[:group] = permitted_group if params[:group].present?
    if params.key?(:monthly_target)
      updates[:monthly_target_cents] = cents_param
      updates[:target_set_by] = "user"
    end

    if category.update(updates)
      redirect_back fallback_location: section_path("budget")
    else
      redirect_back fallback_location: section_path("budget"), alert: category.errors.full_messages.to_sentence
    end
  end

  def destroy
    category = Current.user.budget_categories.find(params[:id])

    if category.transactions.exists?
      category.update!(archived_at: Time.current)
      notice = "#{category.name} archived — its history stays on past months."
    else
      category.destroy!
      notice = "#{category.name} removed."
    end
    redirect_back fallback_location: section_path("budget"), notice: notice
  end

  private
    def permitted_group
      params[:group].presence_in(BudgetCategory::GROUPS) || "needs"
    end

    def cents_param
      return nil if params[:monthly_target].blank?
      (params[:monthly_target].to_f * 100).round
    end
end
