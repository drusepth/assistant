module People
  # Putting a person *into* a group (D-people-circles). Group membership was
  # always just a section tagging, but until now the only thing in the app
  # that wrote one was the section picker inside the Advanced drawer of the
  # person edit form — so groups were born empty and stayed that way, and
  # the chips on the People page pointed at empty rooms.
  #
  # Deliberately still a plain SectionTagging: no join table, and no pulling
  # the person↔item links (Q17) forward. This needs neither.
  module Membership
    module_function

    # Returns the person, or nil when the caller gave neither an existing
    # person nor a name to make one from.
    def add(viewer, section, person_id: nil, name: nil)
      person = Picker.for_group(viewer, section).resolve(person_id: person_id, name: name)
      return nil unless person

      # Idempotent: a double-tap on a phone can't produce two taggings.
      SectionTagging.find_or_create_by!(section: section, taggable: person)
      person
    end

    # The person keeps everything else — their other tags, their circle
    # flag, their page. Same contract as removing the group itself.
    def remove(viewer, section, person_id:)
      person = Person.visible_to(viewer).find_by(id: person_id)
      return nil unless person

      SectionTagging.where(section: section, taggable: person).destroy_all
      person
    end
  end
end
