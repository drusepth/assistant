module Watcher
  # A pet's vaccines are running out (D-pet-vaccinations). Deterministic, over
  # the good-until dates on her record: no date, no nudge, and no record, no
  # nudge — a guessed reminder costs trust (the Q8 lesson), and the card on
  # her page is where an unknown is said out loud instead.
  #
  # One nudge per pet, not per vaccine: rabies and DHPP coming due in the same
  # month are one vet visit, so they are one suggestion naming both. It is
  # keyed by the earliest date among them and by stage — once when it comes
  # due soon, once more if it lapses — so dismissing the heads-up doesn't
  # silence the overdue notice, and a new dose is a new conversation.
  #
  # Only pets still with us are scanned (`Pet.active`), and the nudge retires
  # itself when the world handles it: a newer dose logged, the visit booked,
  # or the pet gone (D-suggestion-lifecycle).
  class PetVaccineDue < Base
    self.section_slugs = %w[ health ]

    def scan
      Pet.visible_to(user).active.includes(:section, :vet).each do |pet|
        due = Pets::VaccineStatus.new(pet, viewer: user).needing_attention
        propose_for(pet, due) if due.any?
      end
      proposals
    end

    # Handled when nothing that was due on the fingerprint's date still
    # needs attention: a new dose moved it, or a booked visit covers it.
    def resolved?(suggestion)
      pet_id = subject_id(suggestion, "pet")
      due_on = suggestion.fingerprint[/due:(\d{4}-\d{2}-\d{2})/, 1]
      return false if pet_id.nil? || due_on.nil?

      pet = Pet.visible_to(user).active.find_by(id: pet_id)
      return true if pet.nil?

      Pets::VaccineStatus.new(pet, viewer: user).needing_attention.none? { |entry| entry.due_on.iso8601 == due_on }
    end

    private
      def propose_for(pet, entries)
        earliest = entries.min_by(&:due_on)
        stage = earliest.state == :overdue ? "overdue" : "soon"
        labels = entries.map(&:label)

        propose(
          fingerprint: "pet:#{pet.id}/due:#{earliest.due_on.iso8601}/#{stage}",
          title: title_for(pet, earliest, labels),
          body: body_for(pet, entries),
          action: action_for(pet, entries),
          sections: [ "health", pet.section.slug ]
        )
      end

      def title_for(pet, earliest, labels)
        what = labels.one? ? labels.first : labels.to_sentence
        if earliest.state == :overdue
          "#{pet.name}'s #{what} #{labels.one? ? "has" : "have"} run out"
        else
          "#{pet.name}'s #{what} #{labels.one? ? "runs" : "run"} out #{earliest.due_on.strftime("%B %-d")}"
        end
      end

      def body_for(pet, entries)
        lines = entries.map do |entry|
          dose = entry.latest
          verb = entry.state == :overdue ? "ran out" : "good until"
          "#{entry.label}: last #{dose.dose? ? "given" : dose.kind_label.downcase} #{dose.given_on.strftime("%b %-d, %Y")}, #{verb} #{dose.due_on.strftime("%b %-d, %Y")}."
        end
        "#{lines.join(" ")} Nothing is booked yet."
      end

      # With a vet on file, the click opens an appointment already titled,
      # filed, and marked as a vaccination visit — which is what flips the
      # card to Booked and retires this. Without one, finding a vet is the
      # real first step.
      def action_for(pet, entries)
        if pet.vet
          path = Rails.application.routes.url_helpers.new_event_path(
            Pets::VaccineStatus.new(pet, viewer: user).booking_params(entries)
          )
          { "path" => path, "accept_label" => "Book the visit" }
        else
          { "tool" => { "slug" => "find_care", "inputs" => { "specialty" => "veterinarian for a #{pet.species_label.downcase}" } } }
        end
      end
  end
end
