# Following a calendar for a place (D-listing-feeds). Two fetch postures,
# the reader's: adding fetches *now*, because a subscription that silently
# fails to exist is worse than a slow form; everything else is a job.
class ListingSourcesController < ApplicationController
  before_action :set_source, only: %i[ destroy refresh ]

  def create
    place = Current.user.places.find(params[:place_id])
    return create_provider(place) if params[:provider].present?

    found = Listings::Discover.call(params.dig(:listing_source, :url))
    source = place.listing_sources.new(url: found.url, kind: found.kind, title: found.title)

    if source.save
      RefreshListingSourceJob.perform_later(source)
      redirect_to return_to_path(places_path),
        notice: "Following #{source.display_title} for #{place.name} — #{found.items.size} #{"listing".pluralize(found.items.size)} found, and it's being checked now."
    else
      redirect_to return_to_path(places_path), alert: source.errors.full_messages.to_sentence
    end
  rescue Listings::Discover::Error => e
    redirect_to return_to_path(places_path), alert: e.message
  end

  def destroy
    @source.destroy!
    redirect_to places_path, notice: "Unfollowed #{@source.display_title}. What you added to your calendar from it stays."
  end

  def refresh
    RefreshListingSourceJob.perform_later(@source)
    redirect_back fallback_location: places_path, notice: "Checking #{@source.display_title}…"
  end

  private
    # The opt-in search (D-listing-feeds §8): a keyed provider queried by
    # the place's point. The consent box is the switch, and it is required
    # here as well as drawn there — a form can't quietly send a location.
    def create_provider(place)
      settings = ListingSource::PROVIDERS[params[:provider].to_s]
      return redirect_to return_to_path(places_path), alert: "Unknown provider." unless settings
      return redirect_to return_to_path(places_path), alert: "Tick the box to confirm you understand what gets sent." unless params[:consent] == "1"

      credentials = params.fetch(:credentials, ActionController::Parameters.new)
        .permit(*settings[:fields].map { |field| field[:key] }).to_h
      source = place.listing_sources.new(url: settings[:url], kind: "provider", provider: params[:provider].to_s,
        title: settings[:label], credentials: credentials)
      missing = settings[:fields].reject { |field| field[:optional] }.find { |field| credentials[field[:key]].blank? }
      return redirect_to return_to_path(places_path), alert: "#{missing[:label]} can't be blank." if missing

      if source.save
        RefreshListingSourceJob.perform_later(source)
        redirect_to return_to_path(places_path), notice: "#{settings[:label]} is on for #{place.name} — searching it now."
      else
        redirect_to return_to_path(places_path), alert: source.errors.full_messages.to_sentence
      end
    end

    def set_source
      @source = ListingSource.where(place: Current.user.places).find(params[:id])
    end
end
