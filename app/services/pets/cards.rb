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
        elsif (celebration = celebration_within(pet))
          "#{celebration.last} #{celebration.first.strftime("%b %-d")}"
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

      def remembered_phrase(pet)
        date = pet.died_on || pet.left_on
        verb = pet.died? ? "" : "Rehomed "
        [ pet.descriptor.presence&.sub(/ · [^·]*old\z/, ""), "#{verb}#{date.strftime("%B %Y")}" ].compact.join(" · ")
      end
  end
end
