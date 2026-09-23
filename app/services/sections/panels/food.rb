module Sections
  module Panels
    # The Food hub (D-food-section; docs/FOOD_PLAN.md §4): the week's meals,
    # the list, what's in the kitchen, ideas, and a strip of recipes — in
    # the order a household reaches for them.
    #
    # Nothing here is filtered to Food-tagged items. The recipe box is read
    # directly, the way the Pets panel reads `Pet`: an untagged soup is still
    # food. The Food *tag* is for the things that are about food without
    # being food objects, and those appear in the browse zone below.
    class Food < Panel
      RECIPES_SHOWN = 6

      def kitchen
        @kitchen ||= Kitchens::Current.for(viewer).tap do |kitchen|
          # Recipes saved since the last visit get filed while you look.
          ResolveFoodsJob.enqueue(kitchen) if Foods::Catalog.new(kitchen).unresolved?
        end
      end

      def owned_kitchen? = kitchen.owned_by?(viewer)

      def other_kitchens? = Kitchen.visible_to(viewer).where.not(id: kitchen.id).exists?

      # Who else can cook here, for the header's avatar stack.
      def cooks
        @cooks ||= begin
          ids = kitchen.access_grants.pluck(:grantee_id) + [ kitchen.user_id ]
          User.where(id: ids).where.not(id: viewer.id).order(:name).to_a
        end
      end

      def household_others = @household_others ||= viewer.household.users.where.not(id: viewer.id).order(:name).to_a

      # D-kitchen: asked once, visibly, and only of the owner with somebody
      # to share with. Nothing is shared until the click.
      # A kitchen already shared from its settings has had its answer.
      def share_prompt?
        owned_kitchen? && kitchen.share_prompt_pending? && household_others.any? && kitchen.access_grants.none?
      end

      # The hub leads with the kitchen itself, so "Nothing in Food yet"
      # under a shopping list would read as if the list didn't count.
      def show_empty_browse? = false

      # Someone else in the house already keeps a kitchen you can't see —
      # the likely story is that you opened Food before they shared theirs.
      def unshared_household_kitchen_owner
        return unless owned_kitchen? && !other_kitchens?

        Kitchen.where(user_id: household_others.map(&:id)).includes(:user).order(:updated_at).last&.user
      end

      # Recently cooked first, then favourites, then the newest — "what we
      # actually eat" leads, the way the library's own sort does.
      def recipes
        @recipes ||= Recipe.visible_to(viewer).with_attached_image.includes(:sections, :user)
          .order(Arel.sql("last_cooked_on IS NULL, last_cooked_on DESC, favorite DESC, recipes.created_at DESC"))
          .limit(RECIPES_SHOWN).to_a
      end

      # The kitchen's first list, made on first use — the hub's list zone
      # always has somewhere to put the first thing typed.
      def list = @list ||= ShoppingList.default_for(kitchen)
      def lists = @lists ||= kitchen.shopping_lists.ordered.to_a
      def open_items = @open_items ||= list.open_items.includes(:added_by, :recipe, :food).to_a
      def basket_items = @basket_items ||= list.basket_items.includes(:checked_by, :recipe).to_a

      # The next seven days from today — on a phone the strip opens on
      # tonight, not on a Monday that's already been eaten.
      def week = @week ||= (Date.current..(Date.current + 6)).to_a

      def meals_by_day
        @meals_by_day ||= kitchen.meals.between(week.first..week.last).in_order.to_a.group_by(&:date)
      end

      # What needs using, then how much is where.
      def expiring = @expiring ||= kitchen.pantry_items.expiring.by_expiry.limit(6).to_a
      def pantry_counts = @pantry_counts ||= kitchen.pantry_items.group(:location).count

      def ideas = @ideas ||= Kitchens::Ideas.new(kitchen, viewer)
      def unlock = @unlock ||= ideas.buy_to_unlock

      def recipes_count = @recipes_count ||= Recipe.visible_to(viewer).count
    end
  end
end
