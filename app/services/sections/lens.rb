module Sections
  # User-created sub-lenses, the D25 mechanism generalized: a custom child
  # section of a seeded parent — hobbies under Hobbies, groups under People
  # (D38) — after which the whole lens machinery (tagging, section pages,
  # calendar filters, sharing grants, the LLM taxonomy listing) applies for
  # free. Lenses are household-shared like the rest of the taxonomy; the
  # items tagged with them stay private per D9.
  module Lens
    module_function

    def find_or_create!(parent_slug, name, fallback_slug:)
      name = normalized(name)
      raise ArgumentError, "a lens needs a name" if name.blank?

      parent = Section.find_by!(slug: parent_slug)
      parent.children.detect { |child| child.name.casecmp?(name) } ||
        parent.children.create!(
          name: name, slug: available_slug(name, fallback_slug), custom: true,
          position: (parent.children.maximum(:position) || 0) + 1
        )
    end

    # The existing lens a free-typed name refers to, if any — tools use
    # this to narrow their context without ever creating lenses as a side
    # effect.
    def named(parent_slug, name)
      name = name.to_s.squish
      return nil if name.blank?

      Section.find_by(slug: parent_slug)&.children&.detect { |child| child.name.casecmp?(name) }
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
