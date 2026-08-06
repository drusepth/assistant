module Hobbies
  # A hobby is a lens (D21): a user-created child section of Hobbies — the
  # first user-written rows in the D12 taxonomy. The lens machinery (tagging,
  # section pages, calendar filters, sharing grants, the LLM taxonomy
  # listing) then applies to each hobby for free. Lenses are household-shared
  # like the rest of the taxonomy; the items tagged with them stay private
  # per D9.
  module Lens
    module_function

    def find_or_create!(name)
      name = normalized(name)
      raise ArgumentError, "a hobby needs a name" if name.blank?

      hobbies = Section.find_by!(slug: "hobbies")
      hobbies.children.detect { |child| child.name.casecmp?(name) } ||
        hobbies.children.create!(
          name: name, slug: available_slug(name), custom: true,
          position: (hobbies.children.maximum(:position) || 0) + 1
        )
    end

    # The existing lens a free-typed hobby name refers to, if any — tools
    # use this to narrow their context without ever creating lenses as a
    # side effect.
    def named(name)
      name = name.to_s.squish
      return nil if name.blank?

      Section.find_by(slug: "hobbies")&.children&.detect { |child| child.name.casecmp?(name) }
    end

    def normalized(name)
      name = name.to_s.squish
      name.sub(/\A\p{Ll}/) { |first| first.upcase }
    end

    # Slugs share one global namespace with the seeded taxonomy (and feed
    # the LLM listing), so a hobby named like a seeded section gets a
    # numbered slug instead of colliding.
    def available_slug(name)
      base = name.parameterize.presence || "hobby"
      slug = base
      counter = 1
      slug = "#{base}-#{counter += 1}" while Section.exists?(slug: slug)
      slug
    end
  end
end
