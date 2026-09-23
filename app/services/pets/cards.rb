module Pets
  # The pets strip on the People page (D-pet-primitive): one card per pet,
  # in the same visual language as the circle and group cards beside it —
  # a face, a name, and one line of signal.
  #
  # Signal order mirrors People::Circles#next_thing: the fact you wanted
  # before you started reading. What's booked, else what care is due, else
  # a birthday worth marking, else an honest invitation.
  class Cards
    include Rails.application.routes.url_helpers

    BIRTHDAY_WINDOW = 30

    Card = Struct.new(:pet, :name, :path, :signal, :gone, keyword_init: true) do
      def gone? = gone
    end

    def self.for(viewer) = new(viewer).cards

    def initialize(viewer)
      @viewer = viewer
    end

    attr_reader :viewer

    # Present tense first, remembered last — two strips, one builder.
    def cards = pets.map { |pet| card(pet) }

    def active_cards = cards.reject(&:gone?)
    def gone_cards = cards.select(&:gone?)

    private
      def pets
        @pets ||= Pet.visible_to(viewer).order(:name).includes(:section).with_attached_avatar.to_a
      end

      def card(pet)
        Card.new(pet: pet, name: pet.name, path: pet_path(pet), gone: !pet.active?,
          signal: pet.active? ? signal(pet) : remembered_phrase(pet))
      end

      def signal(pet)
        [ pet.descriptor.presence, next_thing(pet) ].compact.join(" · ")
      end

      def next_thing(pet)
        if (event = next_events[pet.section_id])
          "#{event.title} · #{event.starts_at.strftime("%b %-d")}"
        elsif (vaccine = due_vaccines[pet])
          "#{vaccine.label} #{vaccine.state == :overdue ? "overdue" : "due #{vaccine.due_on.strftime("%b %-d")}"}"
        elsif (due = due_care[pet]).present?
          "#{due.first.kind.label.downcase} due"
        elsif (celebration = celebration_within(pet))
          "#{celebration.last} #{celebration.first.strftime("%b %-d")}"
        elsif unrecorded.include?(pet.id)
          "Start with #{pet.pronouns.possessive} vaccines →"
        end
      end

      # The honest invitation: a pet with no vaccination on record is pointed
      # at the first thing her page can hold. Once there is one, the card goes
      # quiet rather than nag. One query for every card, not one per pet.
      def unrecorded
        @unrecorded ||= begin
          ids = pets.select(&:active?).map(&:id)
          ids - PetVaccination.where(pet_id: ids).distinct.pluck(:pet_id)
        end
      end

      # One query for every pet's next event rather than one per card — the
      # People::Circles rule, for the same reason.
      def next_events
        @next_events ||= Event.visible_to(viewer)
          .joins(:section_taggings)
          .where(section_taggings: { section_id: pets.map(&:section_id) })
          .where(starts_at: Time.current..)
          .select("events.*", "section_taggings.section_id AS lens_section_id")
          .order(:starts_at)
          .group_by(&:lens_section_id)
          .transform_values(&:first)
      end

      # Care states come from the radar itself, so a card and the tiles on her
      # page can never disagree about what's due.
      def due_care
        @due_care ||= pets.select(&:active?).index_with do |pet|
          Health::CareRadar.new(pet, viewer: viewer).statuses.select { |status| status.state == :due }
        end
      end

      # The first vaccine running out, from the same record her page reads
      # (D-pet-vaccinations) — ahead of the radar's tiles, because a lapsed
      # rabies is the one that stops a kennel booking.
      def due_vaccines
        @due_vaccines ||= pets.select(&:active?).index_with do |pet|
          Pets::VaccineStatus.new(pet, viewer: viewer).needing_attention.first
        end
      end

      def celebration_within(pet)
        date, label = pet.celebration
        return nil unless date

        next_one = next_occurrence(date)
        [ next_one, label ] if next_one <= Date.current + BIRTHDAY_WINDOW
      end

      # Feb 29 falls back to Feb 28 in common years — the Person#next_birthday
      # rule, and the reason that math lives in one place per model.
      def next_occurrence(date, from: Date.current)
        this_year = in_year(date, from.year)
        this_year < from ? in_year(date, from.year + 1) : this_year
      end

      def in_year(date, year)
        Date.new(year, date.month, date.day)
      rescue Date::Error
        Date.new(year, date.month, date.day - 1)
      end

      # Her age is the one part of the descriptor that stops being true, so a
      # remembered card is built from the parts rather than by editing the
      # sentence the living cards use.
      def remembered_phrase(pet)
        date = pet.died_on || pet.left_on
        verb = pet.died? ? "" : "Rehomed "
        [ pet.species_label, pet.breed.presence, "#{verb}#{date.strftime("%B %Y")}" ].compact.join(" · ")
      end
  end
end
