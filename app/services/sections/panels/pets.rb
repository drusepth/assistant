module Sections
  module Panels
    # The Pets hub (D-pets-section): every pet as a card, in the People page's
    # card language, then what the app can do for them. Each pet's lens is a
    # child of this section, so the browse zone below is "everything about any
    # of your pets" for free — and her vet visit is still Health + her name,
    # so the Health page keeps it too.
    class Pets < Panel
      # The routine-care roll-up earns its card only once there are enough
      # pets that the cards stop being an overview — each card already names
      # what's due.
      CARE_SUMMARY_FROM = 3

      # The panel draws the pet tools itself, as one row of buttons: six
      # full-size cards pushed a phone's pets' own tasks and events off the
      # bottom of the page.
      def hidden_tool_slugs = ::Pets::ALL_TOOL_SLUGS

      def pet_cards = @pet_cards ||= ::Pets::Cards.new(viewer)

      def pets = pet_cards.active_cards

      def remembered_pets = pet_cards.gone_cards

      # "Prep for a vet visit" with no pet to prep is noise; "Bringing a pet
      # home" always stays, since it's how the first one arrives.
      def tools
        slugs = active_pets.any? ? ::Pets::CARE_TOOL_SLUGS - %w[ lost_pet ] : []
        (slugs + [ ::Pets::ARRIVAL_TOOL_SLUG ]).map { |slug| Tool.find!(slug) }
      end

      # Kept apart and styled as the urgent one, as on the pet's page — a
      # crisis tool is never just one button among six.
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

      private
        def active_pets
          @active_pets ||= Pet.visible_to(viewer).active.includes(:section).order(:name).to_a
        end
    end
  end
end
