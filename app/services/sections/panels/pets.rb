module Sections
  module Panels
    # The Pets hub (D-pets-section): every pet as a card, in the People page's
    # card language, then what the app can do for them. Each pet's lens is a
    # child of this section, so the browse zone below is "everything about any
    # of your pets" for free — and her vet visit is still Health + her name,
    # so the Health page keeps it too.
    #
    # No tools card: every care tool already lives on each pet's own page with
    # the pet chosen, so a row of them here was the same buttons a second
    # time, in the page's best spot, above the pets' own tasks. What stays is
    # what only the hub can offer, each where it's reached for — the arrival
    # tool on the add tile, and the crisis tool one tap from the cards.
    class Pets < Panel
      # The routine-care roll-up earns its card only once there are enough
      # pets that the cards stop being an overview — each card already names
      # what's due.
      CARE_SUMMARY_FROM = 3

      # The generic Act zone would put six full-size cards above the pets' own
      # tasks and events; the panel places the two it keeps itself.
      def hidden_tool_slugs = ::Pets::ALL_TOOL_SLUGS

      def pet_cards = @pet_cards ||= ::Pets::Cards.new(viewer)

      def pets = pet_cards.active_cards

      def remembered_pets = pet_cards.gone_cards

      # "Bringing a pet home" rides the add tile: it's how the first one
      # arrives, and the next.
      def arrival_tool = Tool.find!(::Pets::ARRIVAL_TOOL_SLUG)

      # Never folded behind a pet's page or a menu — the argument for a crisis
      # tool is that it's one tap away — but a line under the cards, not a
      # button above everything.
      def lost_pet_tool = (Tool.find!("lost_pet") if active_pets.any?)

      # With one pet the form already knows which.
      def tool_inputs(tool)
        return {} unless active_pets.one? && tool.slug != ::Pets::ARRIVAL_TOOL_SLUG

        { pet_id: active_pets.first.id }
      end

      def show_care? = active_pets.size >= CARE_SUMMARY_FROM && care.any?

      # The same rows the Health page's household strip draws, so the two can
      # never disagree about what's due (D-pet-care-radar) — radar tiles and,
      # beside them, the vaccines needing doing (D-pet-vaccinations).
      def care
        @care ||= active_pets.filter_map do |pet|
          tracked = ::Health::CareRadar.new(pet, viewer: viewer).statuses
            .select { |status| status.last_visit || status.next_visit }
          vaccines = ::Pets::VaccineStatus.new(pet, viewer: viewer).entries
            .select { |entry| entry.attention? || entry.state == :booked }
          [ pet, tracked, vaccines ] if tracked.any? || vaccines.any?
        end
      end

      # With a pet on the page, the pet card is the way in — its signal line
      # says where to start — so "Nothing in Pets yet" under it would only
      # read as if the pet didn't count. With no pets, the generic card stays.
      def show_empty_browse? = active_pets.empty?

      private
        def active_pets
          @active_pets ||= Pet.visible_to(viewer).active.includes(:section).order(:name).to_a
        end
    end
  end
end
