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
    end
  end
end
