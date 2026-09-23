module People
  # "Put a person here" (D-person-picker): the one type-to-find field that
  # replaced every address-book <select> — the circle capture, every group
  # card, a group's page, a photo's tags. A dropdown of the whole roster was
  # fine at two contacts and unusable the morning after a CardDAV import
  # drops four hundred into it; a search that returns eight is the same
  # screen at any size.
  #
  # Each place builds its picker with the pool it may draw from and the
  # people already there (who are left out of the suggestions — offering
  # to add Rosa to the group Rosa is in is noise). `matches` answers the
  # combobox as you type; `resolve` answers the form when it's submitted.
  class Picker
    LIMIT = 8

    # The circle is per-user intent (D-people-dashboard): only your own
    # contacts, and not the ones already in it.
    def self.for_circle(viewer)
      new(viewer, pool: viewer.people, present: viewer.people.circle)
    end

    # A group is a shared lens, so it can hold anyone the viewer can see.
    def self.for_group(viewer, group)
      new(viewer, pool: Person.visible_to(viewer), present: Person.in_section(group))
    end

    # Tags name, they never grant: a photo can name anyone the viewer can
    # already see (D-photos-primitive).
    def self.for_photo(viewer, photo)
      new(viewer, pool: Person.visible_to(viewer), present: Person.where(id: photo.photo_people.select(:person_id)))
    end

    def initialize(viewer, pool:, present:)
      @viewer = viewer
      @pool = pool
      @present = present
    end

    # Up to LIMIT people for a typed query: names that start with it first,
    # then a later word that does ("Lee" finds "Anna Lee"), then anything
    # else it appears in — relationship and email included, since "mom" is
    # how people look for their mom. Circle before rolodex within each.
    # Plain search over the user's own rows, not a guess at what anything
    # *is* (D-no-keyword-logic doesn't reach it).
    def matches(query)
      query = query.to_s.squish
      return [] if query.empty?

      like = Person.sanitize_sql_like(query)
      rank = Person.sanitize_sql_array([
        "CASE WHEN people.name LIKE ? THEN 0 WHEN people.name LIKE ? THEN 1 ELSE 2 END",
        "#{like}%", "% #{like}%"
      ])
      @pool.where.not(id: @present.select(:id))
        .where("people.name LIKE :needle OR people.relationship LIKE :needle OR people.email LIKE :needle", needle: "%#{like}%")
        .preload(:linked_user).with_attached_avatar
        .order(Arel.sql(rank), keep_in_touch: :desc)
        .order(Arel.sql("people.name COLLATE NOCASE ASC"))
        .limit(LIMIT).to_a
    end

    # Whether the typed text already names someone in the pool, so the
    # combobox doesn't offer to create a second one.
    def exact(query)
      name = query.to_s.squish
      return nil if name.empty?

      @pool.where("people.name = ? COLLATE NOCASE", name).order(keep_in_touch: :desc, id: :asc).first
    end

    # The submitted form: the picked person, or — for a typed name — the
    # contact who already has that exact name (Enter without picking
    # shouldn't make a duplicate Rosa), or a new contact of the viewer's
    # own (`previously_new_record?` tells the caller which, for anything
    # only a new contact wants — the circle's auto-sort). Returns nil when
    # there's neither a pick nor a name.
    def resolve(person_id: nil, name: nil)
      return @pool.find_by(id: person_id) if person_id.present?
      return nil if name.to_s.squish.empty?

      exact(name) || @viewer.people.create!(name: name.to_s.squish)
    end
  end
end
