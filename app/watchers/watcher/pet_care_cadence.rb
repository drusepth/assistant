module Watcher
  # The checkup-cadence watcher, pointed at the household's animals
  # (D-pet-care-radar). Same discipline as its human twin: a per-kind nudge
  # needs per-kind history — no logged dental, no dental nudge — because a
  # guessed nudge costs trust (the Q8 lesson), and the radar on her page is
  # the pull surface for everything it doesn't know.
  #
  # Only pets still with us are scanned. Nothing about a pet who has died
  # should ever nag, and `Pet.active` is where that is decided once.
  class PetCareCadence < Base
    self.section_slugs = %w[ health ]

    def scan
      Pet.visible_to(user).active.includes(:section).each do |pet|
        Health::CareRadar.new(pet, viewer: user).statuses
          .select { |status| status.state == :due }
          .each { |status| propose_kind(pet, status) }
      end
      proposals
    end

    private
      def propose_kind(pet, status)
        propose(
          fingerprint: "#{pet.id}/#{status.kind.key}/#{period(status.kind)}",
          title: status.kind.book_title,
          body: "#{pet.name}'s last #{status.kind.history_phrase} was #{status.last_visit_on.strftime("%B %Y")} — " \
                "about every #{status.kind.cadence_phrase} is the usual rhythm, and nothing's booked yet.",
          action: book_action(pet, status.kind),
          sections: [ "health", pet.section.slug ]
        )
      end

      # Accepting opens find-care with the vet prefilled, the stay-in-touch
      # convention — except for the kinds that aren't medical, where a groomer
      # has no business in a find-a-doctor tool and a plain task is the honest
      # landing (D-nonclinical-care-kinds).
      def book_action(pet, kind)
        if kind.clinical?
          { "tool" => { "slug" => "find_care", "inputs" => { "specialty" => "#{kind.provider} for a #{pet.species_label.downcase}" } } }
        else
          { "task" => { "title" => kind.book_title } }
        end
      end

      # A dismissed nudge must stay dismissed for about as long as the rhythm
      # it is about. Half a year suits a yearly vaccination and would silence
      # a monthly flea treatment for five cycles, so a short cadence gets a
      # monthly period instead.
      def period(kind)
        return Date.current.strftime("%Ym%m") if kind.short_cadence?

        "#{Date.current.year}h#{Date.current.month <= 6 ? 1 : 2}"
      end
  end
end
