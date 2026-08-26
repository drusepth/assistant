module Sections
  module Panels
    # A pet's lens page (D-pet-primitive). Reached through the owned-lens rung
    # in Panel rather than by slug — a lens is named by the user, and no class
    # can be named after "luna-2".
    #
    # Deliberately thin. This page is the *browse* of everything tagged with
    # her, which the generic zones below already draw well; the curated
    # dashboard is the pet's own page, and the panel's whole job is to say so
    # and get out of the way.
    class PetLens < Panel
      def pet = @pet ||= Pet.visible_to(viewer).find_by(section_id: section.id)

      # Her page is where the care tools belong, prefilled; "Bringing a pet
      # home" is about the pet who isn't here yet.
      def hidden_tool_slugs = [ ::Pets::ARRIVAL_TOOL_SLUG ]
    end
  end
end
