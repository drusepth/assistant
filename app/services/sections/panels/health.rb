module Sections
  module Panels
    # The Health lead panel (docs/HEALTH.md): care radar, household care,
    # Mind, medications, insurance & coverage.
    class Health < Panel
      def hidden_tool_slugs = ::Health::PANEL_TOOL_SLUGS

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

      def coverage_documents
        @coverage_documents ||= ::Health::Coverage.documents(viewer)
      end

      def medications
        @medications ||= viewer.notes.medications.order(:title)
      end

      def last_check_in
        return @last_check_in if defined?(@last_check_in)

        @last_check_in = viewer.tool_runs.where(tool_slug: "check_in", status: :done)
          .order(created_at: :desc).first
      end
    end
  end
end
