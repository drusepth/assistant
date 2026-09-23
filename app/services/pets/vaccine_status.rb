module Pets
  # What a pet's vaccine record says right now (D-pet-vaccinations): per
  # vaccine, whether it is current, due soon, overdue, booked, or has no
  # expiry on record — plus the core vaccines with no record at all, the
  # reactions a vet must hear about, and the vaccination visits on the
  # calendar nobody has said the contents of yet.
  #
  # Derived and deterministic, like the care radar: the latest row per
  # vaccine group decides, so the card, the Health strip, the watcher and the
  # shareable record can never disagree with each other or with the history.
  class VaccineStatus
    # The explicit care_kind a vaccination visit carries. It stays a valid
    # stored value after the radar kind was retired, so a booked visit and the
    # old events the migration marked are read by this, not by their titles.
    VISIT_KIND = "pet_vaccinations".freeze

    # "Due soon" starts this far out, or a third of the dose's own interval
    # when that is shorter: a month's notice suits a yearly rabies and would
    # announce a puppy's three-week booster the day it was given.
    LEAD = 30.days

    Entry = Data.define(:group_key, :label, :latest, :doses, :booked_visit) do
      def due_on = latest.due_on

      def lead_days
        return LEAD.in_days.to_i unless due_on

        [ LEAD.in_days.to_i, ((due_on - latest.given_on).to_i / 3.0).floor ].min.clamp(1, LEAD.in_days.to_i)
      end

      def state
        return :no_expiry unless due_on
        return :booked if booked_visit && due_on <= Date.current + lead_days
        return :overdue if due_on < Date.current
        return :due_soon if due_on <= Date.current + lead_days

        :current
      end

      # Needs doing: what the watcher speaks about and the Health strip flags.
      def attention? = %i[ due_soon overdue ].include?(state)

      def reactions = doses.select { |dose| dose.reaction.present? }
    end

    def initialize(pet, viewer:)
      @pet = pet
      @viewer = viewer
    end

    attr_reader :pet, :viewer

    # Every row, newest first — the history view and the shareable record.
    def doses
      @doses ||= pet.pet_vaccinations.includes(:vet, :document).chronological.to_a
    end

    def any? = doses.any?

    # One Entry per vaccine group, the ones needing attention first, then by
    # when they come due (no expiry last), then by name.
    def entries
      @entries ||= doses.group_by(&:group_key).map do |group_key, rows|
        Entry.new(group_key: group_key, label: rows.first.vaccine_label, latest: rows.first, doses: rows, booked_visit: booked_visit)
      end.sort_by { |entry| [ entry.attention? ? 0 : 1, entry.due_on || Date.new(9999), entry.label.downcase ] }
    end

    def needing_attention = entries.select(&:attention?)

    # The core vaccines for her species with no row at all — a gap, stated
    # plainly, never an alarm. Empty for species the catalog doesn't list.
    def missing_core
      logged = doses.map(&:vaccine_key).compact.to_set
      Pets::Vaccines.core(pet.species).reject { |vaccine| logged.include?(vaccine.key) }
    end

    def reactions = doses.select { |dose| dose.reaction.present? }

    # The next vaccination visit on the calendar, whoever booked it — the
    # spouse who drove the dog booked the dog's visit (D-pet-care-radar).
    def booked_visit
      return @booked_visit if defined?(@booked_visit)

      @booked_visit = visits.where(starts_at: Time.current..).order(:starts_at).first
    end

    # Past vaccination visits with no doses logged against them — the prompt
    # that turns "the dog had shots in June" into what the shots were.
    # Nothing is invented from their titles; the owner fills in what they know.
    def unlogged_visits
      @unlogged_visits ||= visits.where(starts_at: ...Time.current)
        .where.not(id: PetVaccination.where.not(event_id: nil).select(:event_id))
        .order(starts_at: :desc).limit(5).to_a
    end

    private
      def visits
        Event.visible_to(viewer).in_section(pet.section_id).where(care_kind: VISIT_KIND)
      end
  end
end
