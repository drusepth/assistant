module Sections
  module Panels
    # A group's own page (D-people-circles): the members, and the ways to
    # change who's in it. Claimed by parent slug rather than by its own —
    # group slugs are whatever the user typed — so every custom lens under
    # People lands here and nowhere else does.
    #
    # Removal lives here rather than on the grid card: hovering a face in a
    # grid to reveal a destructive control is how someone removes their mom
    # by accident.
    class PeopleLens < Panel
      def partial = "sections/panels/people_lens"

      # The panel renders the members itself, with the leave-the-group
      # control the generic person grid has no place for.
      def hidden_browse = %i[ people ]

      def members
        @members ||= Person.visible_to(viewer).in_section(section)
          .order(:name).preload(:linked_user).with_attached_avatar
      end
    end
  end
end
