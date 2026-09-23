# The pet tools, and who should be offered them (D-pet-primitive).
#
# `Tool.for_section` flows a tool registered on a parent down to every child,
# which is right for the taxonomy and wrong for a household with no animals:
# "Prep for a vet visit" on the Health page of a petless house is noise, and
# "My pet is missing" on the book club's page is worse. Panels curate their
# own Act zone (`hidden_tool_slugs`, D37), so the gate lives here — one list,
# read by the panels that need it, and no shared file changes.
module Pets
  # Every tool that takes a pet: without one, its form has nothing to offer.
  CARE_TOOL_SLUGS = %w[ pet_care vet_visit_prep decode_vet_estimate compare_pet_insurance lost_pet ].freeze

  # The one a household with no pets might genuinely want.
  ARRIVAL_TOOL_SLUG = "new_pet".freeze

  ALL_TOOL_SLUGS = (CARE_TOOL_SLUGS + [ ARRIVAL_TOOL_SLUG ]).freeze

  module_function

  # What a page should hide: the care tools, until there is an animal to care
  # for. "Bringing a pet home" always stays — it is how the first one arrives.
  def hidden_tool_slugs(viewer)
    Pet.visible_to(viewer).active.exists? ? [] : CARE_TOOL_SLUGS
  end
end
