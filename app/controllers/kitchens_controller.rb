# The kitchen container itself (D-kitchen): its settings page, making another
# one, and which one the Food hub opens on. What happens *in* a kitchen —
# lists, the fridge, the plan — lives in its own controllers, all of which
# go through `Kitchens::Scoped`.
class KitchensController < ApplicationController
  before_action :set_visible_kitchen, only: %i[ edit select ]
  before_action :set_own_kitchen, only: %i[ update destroy answer_share ]

  def edit
    @owned = @kitchen.owned_by?(Current.user)
    @kitchens = Kitchen.visible_to(Current.user).includes(:user).order(:name)
  end

  def create
    kitchen = Current.user.kitchens.new(name: params.dig(:kitchen, :name).presence || Kitchen::DEFAULT_NAME)

    if kitchen.save
      Current.user.update!(current_kitchen: kitchen)
      redirect_to edit_kitchen_path(kitchen), notice: "#{kitchen.name} is ready."
    else
      redirect_back fallback_location: food_path, alert: kitchen.errors.full_messages.to_sentence
    end
  end

  def update
    if @kitchen.update(params.expect(kitchen: [ :name ]))
      @kitchen.broadcast_change
      redirect_to edit_kitchen_path(@kitchen), notice: "Kitchen renamed."
    else
      redirect_to edit_kitchen_path(@kitchen), alert: @kitchen.errors.full_messages.to_sentence
    end
  end

  def destroy
    @kitchen.destroy!
    redirect_to food_path, notice: "#{@kitchen.name} deleted, with its lists, fridge and plan. Your recipes are untouched."
  end

  # The hub's switcher, for someone who can see more than one kitchen.
  def select
    Current.user.update!(current_kitchen: @kitchen)
    redirect_to food_path
  end

  # The share-this-kitchen card (D-kitchen): nothing is shared until the
  # click, and the card leaves once answered either way.
  def answer_share
    if params[:share] == "everyone"
      Current.user.household.users.where.not(id: Current.user.id).find_each do |member|
        Current.user.granted_access_grants.find_or_create_by!(grantee: member, subject: @kitchen)
      end
      notice = "Shared. Everyone in the household can now add to the lists and change the fridge."
    else
      notice = "Kept private. You can share it any time from the kitchen's settings."
    end
    @kitchen.update!(share_prompt_answered_at: Time.current)

    redirect_to food_path, notice: notice
  end

  private
    def set_visible_kitchen
      @kitchen = Kitchen.visible_to(Current.user).find(params[:id])
    end

    def set_own_kitchen
      @kitchen = Current.user.kitchens.find(params[:id])
    end
end
