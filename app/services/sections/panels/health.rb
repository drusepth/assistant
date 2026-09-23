module Sections
  module Panels
    # The Health lead panel (docs/HEALTH.md): care radar, household care,
    # Mind, medications, allergies, insurance & coverage.
    class Health < Panel
      # The panel's own tools, plus the pet tools until this household has a
      # pet (::Pets.hidden_tool_slugs) — "Prep for a vet visit" on a petless
      # Health page is noise.
      def hidden_tool_slugs = ::Health::PANEL_TOOL_SLUGS + ::Pets.hidden_tool_slugs(viewer)

      def care_statuses
        @care_statuses ||= ::Health::CareRadar.new(viewer).statuses
      end

      # Other household members' care radars, over exactly the events they
      # share with the viewer (visible_to is the only read path — a member
      # who shares nothing simply doesn't appear). Kids are users too; this
      # is how a parent sees the kid's dentist visit they'll be driving to.
      def family_care
        @family_care ||= viewer.household.users.where.not(id: viewer.id).order(:name).filter_map do |member|
          tracked = ::Health::CareRadar.new(member, viewer: viewer).statuses
            .select { |status| status.last_visit || status.next_visit }
          [ member, tracked ] if tracked.any?
        end
      end

      # Pets are members of the household who can't log in
      # (D-pet-care-radar), so they join this strip as rows without a login:
      # the visibility wall is the pet's own grants rather than a member's
      # sharing, and only pets still with us are tracked.
      #
      # Each row also carries the vaccines that need doing (D-pet-vaccinations)
      # — "Rabies due Jun 3" — from her vaccine record, which is not a radar
      # kind because each vaccine runs its own clock.
      def pet_care
        @pet_care ||= Pet.visible_to(viewer).active.includes(:section).filter_map do |pet|
          tracked = ::Health::CareRadar.new(pet, viewer: viewer).statuses
            .select { |status| status.last_visit || status.next_visit }
          vaccines = ::Pets::VaccineStatus.new(pet, viewer: viewer).entries
            .select { |entry| entry.attention? || entry.state == :booked }
          [ pet, tracked, vaccines ] if tracked.any? || vaccines.any?
        end
      end

      def coverage_documents
        @coverage_documents ||= ::Health::Coverage.documents(viewer)
      end

      def medications
        @medications ||= viewer.notes.medications.order(:title)
      end

      def allergies
        @allergies ||= viewer.notes.allergies.by_severity
      end

      def last_check_in
        return @last_check_in if defined?(@last_check_in)

        @last_check_in = viewer.tool_runs.where(tool_slug: "check_in", status: :done)
          .order(created_at: :desc).first
      end
    end
  end
end
