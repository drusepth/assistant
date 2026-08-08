class NotifyJob < ApplicationJob
  queue_as :default

  # titles: what may appear on a lock screen (counts/titles only — D22).
  # summary overrides the default suggestion phrasing for other speakers
  # (the mail digest pointer, urgent alerts) — still header-built text.
  def perform(user, titles, summary: nil)
    Notifications::Deliver.new(user, titles: titles, summary: summary).call
  end
end
