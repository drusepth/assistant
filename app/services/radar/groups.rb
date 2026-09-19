module Radar
  # The Meetup groups the user belongs to, as calendars offered under each
  # place (D-radar-accounts): typed on the account, rewritten to the
  # group's iCal export by discovery, followed only by a tick. Nothing here
  # subscribes anything.
  class Groups
    Group = Data.define(:slug, :url) do
      def name = slug.tr("-_", "  ").squish.capitalize
    end

    def self.for(user) = new(user).all

    def initialize(user)
      @user = user
    end

    def all
      @all ||= @user.linked_accounts.where(provider: "meetup").flat_map { |account|
        next [] unless account.allows?("groups")

        account.credentials["groups"].to_s.split(/[\s,;]+/).map { |slug| slug.strip.delete_prefix("https://www.meetup.com/").delete_suffix("/") }
          .select { |slug| slug.match?(/\A[A-Za-z0-9_-]+\z/) }
          .map { |slug| Group.new(slug: slug, url: "https://www.meetup.com/#{slug}/events/ical/") }
      }.uniq(&:slug)
    end

    # The groups not yet followed for this place.
    def unfollowed_for(place)
      followed = place.listing_sources.map(&:url).to_set
      all.reject { |group| followed.include?(group.url) }
    end
  end
end
