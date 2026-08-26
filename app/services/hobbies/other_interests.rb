module Hobbies
  # The catch-all lens (D-hobby-feeds). Every feed has a hobby or has this
  # one, and that invariant is the whole point: no query anywhere carries an
  # "or untagged" branch, no surface carries a special lane, and the hub's
  # grid is one loop over `hobbies.children`.
  #
  # It is an ordinary child section of Hobbies with two differences from a
  # user's hobby, both deliberate:
  #
  #   - it is found and created **by slug**, never by name, so a user who
  #     names a hobby "Other interests" gets `other-interests-2` from
  #     Sections::Lens and can't take this row out from under the app;
  #   - it is `custom: false`, because the user never said they do this for
  #     fun. That also hides the lens page's "Remove this hobby" button
  #     (which reads `custom?`) and keeps HobbiesController#destroy — which
  #     finds through `Section.custom` — from being able to delete it. The
  #     invariant is protected at the controller layer for free.
  module OtherInterests
    SLUG = "other-interests".freeze
    NAME = "Other Interests".freeze

    module_function

    def find = Section.find_by(slug: SLUG)

    def catch_all?(section) = section&.slug == SLUG

    # Created the first time a feed needs it, rather than seeded, so an
    # instance that files everything by hand never grows the row.
    def find_or_create!
      find || create!
    rescue ActiveRecord::RecordNotUnique
      # Two feeds classified concurrently; whoever lost the race just reads.
      find
    end

    # Everything a feed can be filed under, catch-all last: it is where
    # things land, so it reads as the floor of the grid rather than as a
    # hobby that happens to sort under O.
    def lenses(parent = Section.find_by(slug: "hobbies"))
      return [] unless parent

      parent.children.partition { |child| !catch_all?(child) }.flatten
    end

    # The invariant, applied. Feeds are handed in (rather than fetched) so
    # callers can act on exactly the rows a hobby's deletion stranded —
    # `section_taggings` is `dependent: :destroy`, so those taggings are
    # already gone by the time anybody can look for them.
    def absorb!(feeds)
      orphans = Array(feeds).reject { |feed| feed.sections.any? }
      return [] if orphans.empty?

      lens = find_or_create!
      orphans.each { |feed| feed.sections = [ lens ] }
      orphans
    end

    private_class_method def self.create!
      parent = Section.find_by!(slug: "hobbies")
      parent.children.create!(
        name: NAME, slug: SLUG, custom: false,
        position: (parent.children.maximum(:position) || 0) + 1
      )
    end
  end
end
