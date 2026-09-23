module Sections
  module Panels
    # The Pets hub (D-pets-section): every pet as a card, in the People page's
    # card language, then what care is booked or due across all of them. Each
    # pet's lens is a child of this section, so the browse zone below is
    # "everything about any of your pets" for free — and her vet visit is
    # still Health + her name, so the Health page keeps it too.
    class Pets < Panel
      # "Prep for a vet visit" with no pet to prep is noise; "Bringing a pet
      # home" always stays, since it's how the first one arrives.
      def hidden_tool_slugs = ::Pets.hidden_tool_slugs(viewer)

      def pet_cards = @pet_cards ||= ::Pets::Cards.new(viewer)

      def pets = pet_cards.active_cards

      def remembered_pets = pet_cards.gone_cards

      # The same rows the Health page's household strip draws, so the two can
      # never disagree about what's due (D-pet-care-radar).
      def care
        @care ||= Pet.visible_to(viewer).active.includes(:section).order(:name).filter_map do |pet|
          tracked = ::Health::CareRadar.new(pet, viewer: viewer).statuses
            .select { |status| status.last_visit || status.next_visit }
          [ pet, tracked ] if tracked.any?
        end
      end
    end
  end
end
