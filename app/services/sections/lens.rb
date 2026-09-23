module Sections
  # User-created sub-lenses, the D25 mechanism generalized: a custom child
  # section of a seeded parent — hobbies under Hobbies, groups under People
  # (D-people-dashboard) — after which the whole lens machinery (tagging, section pages,
  # calendar filters, sharing grants, the LLM taxonomy listing) applies for
  # free. Lenses are household-shared like the rest of the taxonomy; the
  # items tagged with them stay private per D9.
  module Lens
    module_function

    def find_or_create!(parent_slug, name, fallback_slug:)
      name = normalized(name)
      raise ArgumentError, "a lens needs a name" if name.blank?

      parent = Section.find_by!(slug: parent_slug)
      parent.children.unowned.detect { |child| child.name.casecmp?(name) } ||
        parent.children.create!(
          name: name, slug: available_slug(name, fallback_slug), custom: true,
          position: (parent.children.maximum(:position) || 0) + 1
        )
    end

    # Always a new lens, even when one of that name exists. Groups are
    # find-or-create — typing "Church" twice means the same church — but a
    # record that *owns* its lens can never share one: two dogs called Rex
    # (usually one remembered and one new) are two pets, two pages and two
    # sets of tags, so the second takes `rex-2` (D-pet-primitive). The owner
    # is written on the row (D-owned-lens) so nothing else has to guess.
    def create!(parent_slug, name, fallback_slug:, owner_type:)
      name = normalized(name)
      raise ArgumentError, "a lens needs a name" if name.blank?

      parent = Section.find_by!(slug: parent_slug)
      parent.children.create!(
        name: name, slug: available_slug(name, fallback_slug), custom: true, owner_type: owner_type,
        position: (parent.children.maximum(:position) || 0) + 1
      )
    end

    # The existing lens a free-typed name refers to, if any — tools use
    # this to narrow their context without ever creating lenses as a side
    # effect. Only the lenses the user made: a group called "Dimitri" is not
    # the cat, and "find or create" must never hand back an owned lens.
    def named(parent_slug, name)
      name = name.to_s.squish
      return nil if name.blank?

      Section.find_by(slug: parent_slug)&.children&.unowned&.detect { |child| child.name.casecmp?(name) }
    end

    def normalized(name)
      name = name.to_s.squish
      name.sub(/\A\p{Ll}/) { |first| first.upcase }
    end

    # Slugs share one global namespace with the seeded taxonomy (and feed
    # the LLM listing), so a lens named like a seeded section gets a
    # numbered slug instead of colliding.
    def available_slug(name, fallback)
      base = name.parameterize.presence || fallback
      slug = base
      counter = 1
      slug = "#{base}-#{counter += 1}" while Section.exists?(slug: slug)
      slug
    end
  end
end
