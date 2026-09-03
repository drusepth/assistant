module Landing
  # A day-sized thing the document asks of you: "bring a stool sample to
  # the next visit", "return the signed form by Friday".
  class Task < Base
    self.description = "a small concrete action the document asks the reader to take"
    self.produces = "tasks"

    field :title, "the action, completable in a day", required: true
    field :due_on, "only when a real deadline is stated", type: :date
    field :notes, "what the document says about it", type: :text

    def land!(attributes, sections:)
      due_on = parsed_date(attributes["due_on"])
      task = user.tasks.create!(
        title: attributes["title"], notes: attributes["notes"], due_on: due_on,
        bucket: due_on && due_on <= Date.current ? :today : :later
      )
      tag(task, sections)
    end

    def duplicate_of(attributes)
      ::Task.visible_to(user).open.where("LOWER(tasks.title) = ?", attributes["title"].to_s.downcase).first
    end

    def preview(attributes)
      Preview.new(kind: kind, title: attributes["title"], detail: attributes["notes"], date: attributes["due_on"])
    end
  end
end
