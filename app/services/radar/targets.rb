module Radar
  # The closed set the matcher selects from (D-event-radar §5.1): every hobby
  # lens with its per-user brief beside it, one interest brief for what isn't
  # a hobby, one causes brief for what the person would give time to. The
  # model picks a key from this list or leaves the row out; a key that isn't
  # here is dropped before anything is written.
  #
  # Briefs are prose the user owns: nothing compares them to anything, so
  # they can't be wrong the way a rule can. A blank causes brief is the
  # volunteering switch for that member — no target, nothing matched.
  class Targets
    Target = Data.define(:key, :name, :brief, :section) do
      def household? = key == HappeningMatch::HOUSEHOLD
      def causes? = key == HappeningMatch::CAUSES
      def line = "#{key} — #{name}#{" — #{brief}" if brief.present?}"
    end

    def self.for(user) = new(user).all

    def initialize(user)
      @user = user
    end

    def all
      @all ||= hobby_targets + subject_targets + [ household_target, causes_target ].compact
    end

    def by_key = @by_key ||= all.index_by(&:key)

    def empty? = all.empty?

    private
      def hobby_targets
        lenses = HobbyBrief.routable_sections(@user)
        briefs = HobbyBrief.where(user: @user, section: lenses).index_by(&:section_id)
        lenses.map do |lens|
          Target.new(key: "section:#{lens.id}", name: lens.name, brief: briefs[lens.id]&.description, section: lens)
        end
      end

      # What someone in the house is learning (D-event-radar §5.1): a
      # planetarium talk reaches the astronomy course. The subject's
      # interest frame is the sentence; the subject is the user's own.
      def subject_targets
        @user.subjects.active.map do |subject|
          Target.new(key: "subject:#{subject.id}", name: "Learning #{subject.title}", brief: subject.interest_frame, section: nil)
        end
      end

      def household_target
        return nil if @user.radar_brief.blank?

        Target.new(key: HappeningMatch::HOUSEHOLD, name: "The household, beyond any one hobby",
          brief: @user.radar_brief, section: nil)
      end

      def causes_target
        return nil if @user.causes_brief.blank?

        Target.new(key: HappeningMatch::CAUSES, name: "Volunteering, a cause to give time to",
          brief: @user.causes_brief, section: nil)
      end
  end
end
