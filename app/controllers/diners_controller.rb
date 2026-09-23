# Who eats from this kitchen and what they can't (D-food-suggestions) —
# written down by the household, used only to leave dishes out.
class DinersController < ApplicationController
  include KitchenScoped

  def create
    diner = @kitchen.diners.new(diner_params)
    if diner.save
      kitchen_changed!
      redirect_to edit_kitchen_path(@kitchen, anchor: "diners"), notice: "#{diner.name} added."
    else
      redirect_to edit_kitchen_path(@kitchen, anchor: "diners"), alert: diner.errors.full_messages.to_sentence
    end
  end

  def update
    diner = @kitchen.diners.find(params[:id])
    diner.update!(diner_params)
    kitchen_changed!
    redirect_to edit_kitchen_path(@kitchen, anchor: "diners"), notice: "#{diner.name} saved."
  end

  def destroy
    @kitchen.diners.find(params[:id]).destroy!
    kitchen_changed!
    redirect_to edit_kitchen_path(@kitchen, anchor: "diners")
  end

  private
    # A household member, when linked, must be one who can cook here.
    def diner_params
      attributes = params.expect(diner: [ :name, :diet_note, :user_id, allergens: [] ])
      if attributes[:user_id].present?
        member = @kitchen.cooks.find_by(id: attributes[:user_id])
        attributes[:user_id] = member&.id
        attributes[:name] = member.name if member && attributes[:name].blank?
      end
      attributes
    end
end
