# The job scout's sources (D-career-web): paste a feed or board link, the kind is
# sniffed on save, and the scout scans it on the agent cadence.
class JobFeedsController < ApplicationController
  def create
    feed = Current.user.job_feeds.new(params.expect(job_feed: [ :url, :label, :api_key ]))
    if feed.save
      redirect_to section_path("career"), notice: "#{feed.display_label} added — the scout checks it on your agent schedule."
    else
      redirect_to section_path("career"), alert: feed.errors.full_messages.to_sentence
    end
  end

  def destroy
    feed = Current.user.job_feeds.find(params[:id])
    feed.destroy!
    redirect_to section_path("career"), notice: "#{feed.display_label} removed."
  end
end
