# What counts as a hobby, as words (D-story-matching).
#
# The whole surface is add-a-word, remove-a-word — and that is the point.
# The rule that carries a broad feed's stories into a hobby is a list the
# user can read, edit and empty, on the hobby's own page, whether or not a
# model ever wrote a line of it. Every change re-runs the backfill, so the
# river answers immediately rather than at the next refresh.
class WatchlistsController < ApplicationController
  before_action :set_section
  before_action :set_watchlist

  KINDS = %w[ terms negatives ].freeze

  def add_term
    @watchlist.save! if @watchlist.new_record?
    changed = @watchlist.add(params[:term], kind: kind)
    rematch if changed

    back alert: ("A term is a word or a short phrase — that one can't be matched on." unless changed)
  end

  def remove_term
    @watchlist.remove(params[:term], kind: kind)
    rematch
    back
  end

  # "Suggest words" — the one model call, asked for out loud (§4.2).
  def author
    if Feeds::Watchlists::Author.enqueue(Current.user, @section)
      back notice: "Reading your feeds for words that mean #{@section.name}…"
    else
      back alert: "No model is configured, so the words here are yours to type."
    end
  end

  # Un-pause a rule this feed flooded (§6). The backfill runs again, so
  # whatever the user narrowed takes effect on what is already here.
  def resume
    feed = Current.user.feeds.find_by(id: params[:feed_id])
    return back(alert: "That feed is gone.") unless feed

    @watchlist.resume!(feed)
    rematch
    back notice: "#{@section.name} is watching #{feed.display_title} again."
  end

  private
    def set_section
      @section = Section.find_by(id: params[:section_id])
      back(alert: "That isn't a hobby.") unless watchable?
    end

    # A watchlist belongs to a hobby lens, never to the catch-all: Other
    # Interests is where a story lands when nothing claims it, so a rule
    # that routed *into* it would have nothing to mean.
    def watchable?
      @section&.parent&.slug == "hobbies" && !Hobbies::OtherInterests.catch_all?(@section)
    end

    def set_watchlist = @watchlist = Watchlist.for(Current.user, @section)

    def kind = KINDS.include?(params[:kind]) ? params[:kind].to_sym : :terms

    def rematch
      MatchStoriesJob.perform_later(@watchlist) if @watchlist.persisted?
    end

    def back(notice: nil, alert: nil)
      redirect_back fallback_location: @section ? section_path(@section.slug) : root_path,
        notice: notice, alert: alert
    end
end
