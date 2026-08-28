class NotifyJob < ApplicationJob
  queue_as :default

  # titles: what may appear on a lock screen (counts/titles only — D22).
  # summary overrides the default suggestion phrasing for other speakers
  # (the mail digest pointer, urgent alerts) — still header-built text.
  # suggestion_ids: the batch a one-tap decision link should open
  # (D-decision-links). Ids rather than records, so a suggestion retired
  # between the scan and the send costs the job nothing — the page filters
  # to what is still actionable anyway.
  def perform(user, titles, summary: nil, suggestion_ids: nil)
    link = Notifications::DecisionLink.url_for(suggestion_ids) if suggestion_ids.present?
    Notifications::Deliver.new(user, titles: titles, summary: summary, link: link).call
  end
end
