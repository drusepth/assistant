module Pets
  # A pet's papers (D-pet-primitive/W4). Vaccination records, adoption papers,
  # microchip registration, insurance policies, lab results: all of them are
  # Documents the vault already reads, tagged with her lens, so this needs no
  # new machinery at all — only an order.
  #
  # Policy-shaped documents lead, because they are the ones you need at the
  # worst moment. The shape test is Health::Coverage's own heuristic (with the
  # owner's pin still beating the keywords), reused rather than re-written:
  # a pet policy and a human one read the same to a keyword.
  class Papers
    def self.for(pet, viewer, limit: 8)
      Document.visible_to(viewer).in_section(pet.section)
        .includes(:sections, :user)
        .sort_by { |document| [ Health::Coverage.match?(document) ? 0 : 1, -document.created_at.to_i ] }
        .first(limit)
    end

    def self.policy?(document) = Health::Coverage.match?(document)
  end
end
