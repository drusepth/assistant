module Sections
  module Panels
    # One hobby's page (D-hobby-feeds). Reached through Panel's parent-lens
    # fallback rather than by name, because a lens is a row the user made and
    # no class can be named after its slug.
    #
    # This is the "filter to one hobby" half of the hub: the same river, the
    # same density, narrowed to the feeds filed under this lens — with the
    # everything-view one link away. Deeper than the hub card (a screenful,
    # not a taste) and shallower than /reader (no filter rows, no paging):
    # the page's other zones are what you came for, and the river is the part
    # that changed since yesterday.
    class HobbiesLens < Panel
      PREVIEW = 12

      def row = @row ||= ::Hobbies::Rivers.for(viewer, [ section ], preview: PREVIEW).sole

      def feeds = row.feeds
      def items = row.items
      def unread_count = row.unread_count

      # What this hobby means, in the user's own words (D-story-matching):
      # the sentence the router reads when it decides whether a broad feed's
      # story belongs here. Unsaved until somebody edits it or the model
      # drafts one — a hobby nobody has described shouldn't cost a row.
      def brief = @brief ||= ::HobbyBrief.for(viewer, section)

      # The catch-all has no brief: it is where a story lands when nothing
      # claims it, so routing *into* it would mean nothing.
      def brief? = !::Hobbies::OtherInterests.catch_all?(section)

      def routed_this_week
        @routed_this_week ||= brief.routings.live.since(1.week.ago).count
      end

      # What the user has taken back out. It is not a rule that changed —
      # these titles are shown to the model as examples next time.
      def corrections
        @corrections ||= brief.routings.rejected.joins(:feed_item)
          .order(rejected_at: :desc).limit(3).pluck(:title)
      end

      # The broad feeds whose stories get read one at a time. A household
      # with none of them is paying nothing and should be told so.
      def broad_feeds = @broad_feeds ||= viewer.feeds.active.where(broad: true).to_a

      def model? = viewer.household.model_profile&.configured?

      # What's on near the user's places that the model judged to be *this*
      # hobby's (D-event-radar) — the "Birding, near you" list the whole
      # feature exists to produce, on the page where somebody has already
      # decided to spend time on birding. Nothing when there are no places.
      def nearby
        @nearby ||= viewer.places.exists? ? ::Radar::River.new(viewer, section: section).items(PREVIEW) : []
      end

      def places? = viewer.places.exists?
    end
  end
end
