module People
  # A group is a lens (D38 §6): family, church, the D&D table, the
  # mutual-aid crew — a user-created child section of People riding the
  # generalized D25 mechanism. Group pages, calendar filters, and sharing
  # all fall out of the lens machinery; People tools surface on every group
  # page via the parent-tool rule.
  module Group
    module_function

    def find_or_create!(name) = Sections::Lens.find_or_create!("people", name, fallback_slug: "group")

    def named(name) = Sections::Lens.named("people", name)
  end
end
