# The one door into a kitchen's rows (D-kitchen). Lists, pantry items, meals,
# foods and diners have no owner of their own and no `visible_to` — they are
# reached only through a kitchen the viewer can see, and seeing a kitchen is
# being allowed to cook in it.
module KitchenScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_kitchen
  end

  private
    def set_kitchen
      @kitchen = Kitchen.visible_to(Current.user).find(params[:kitchen_id])
    end

    # After a write: tell everyone else's open page, then go back.
    def kitchen_changed!
      @kitchen.broadcast_change
    end
end
