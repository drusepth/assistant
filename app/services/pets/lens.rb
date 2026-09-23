module Pets
  # A pet's lens (D-pet-primitive): a custom child section of Pets
  # (D-pets-section), riding the same generalized D25 mechanism as hobbies and
  # groups. The parent matters less than what the lens buys, which is that
  # "about Rex" becomes a tag every existing form, query, filter and grant
  # already understands.
  module Lens
    PARENT = "pets".freeze

    module_function

    # Always a fresh lens: a pet owns hers, so she can never share one with
    # another pet of the same name (Sections::Lens.create!).
    def create!(name) = Sections::Lens.create!(PARENT, name, fallback_slug: "pet")

    # Renaming a pet renames her lens but never its slug: slugs are a global
    # namespace feeding URLs and the LLM's taxonomy listing, and rewriting one
    # breaks bookmarks for a cosmetic gain. (`available_slug` already numbers
    # the second Luna, so the collision case is handled at creation.)
    def rename!(section, name)
      name = Sections::Lens.normalized(name)
      section.update!(name: name) unless name.blank? || section.name == name
    end

    # Every pet lens in the instance — the set a user's own care radar has to
    # subtract (D-pet-care-radar).
    def section_ids = Pet.distinct.pluck(:section_id)
  end
end
