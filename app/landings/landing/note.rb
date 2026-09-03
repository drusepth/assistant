module Landing
  # The catch-all for a fact worth keeping that has no shape of its own:
  # "Dr. Alvarez says the limp is arthritis, not the cruciate."
  class Note < Base
    self.description = "a fact worth remembering that fits no other kind — what someone said, a reference number, a result"
    self.produces = "notes"

    field :title, "a short label", required: true
    field :body, "the fact, in the document's own words", type: :text

    def land!(attributes, sections:)
      note = user.notes.create!(title: attributes["title"], body: attributes["body"].presence || attributes["title"])
      tag(note, sections)
    end

    def duplicate_of(attributes)
      ::Note.visible_to(user).plain.where("LOWER(notes.title) = ?", attributes["title"].to_s.downcase).first
    end

    def preview(attributes)
      Preview.new(kind: kind, title: attributes["title"], detail: attributes["body"], date: nil)
    end
  end
end
