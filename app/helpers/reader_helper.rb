# The reader's small view decisions (D-feed-reader), kept out of
# SectionsHelper on purpose — that file is a merge hot spot and a section
# feature has no business editing it (D37).
module ReaderHelper
  FILTER_LABELS = { "unread" => "Unread", "saved" => "Saved", "all" => "Everything" }.freeze

  # A filter chip that keeps the rest of the river's state — swapping the
  # filter shouldn't silently drop the hobby you were reading.
  def reader_chip(label, params_override, active:)
    link_to label, reader_path(request.query_parameters.except("offset").merge(params_override)),
      class: "chip #{active ? "bg-ink text-white" : "bg-stone-100 text-stone-700 hover:bg-stone-200"}"
  end

  # "2h ago", "3d ago" — a river is scanned, and a full date is four words
  # where one belongs.
  def reader_age(time)
    return nil if time.blank?

    seconds = Time.current - time
    return "just now" if seconds < 2.minutes

    "#{time_ago_in_words(time)} ago"
  end

  # An item's link goes to a stranger's site: new tab, no window handle back
  # into the app, and no referrer telling them which of our pages sent you.
  OUTBOUND = { target: "_blank", rel: "noopener noreferrer nofollow" }.freeze

  # Only http(s) reaches an href. Feeds are hostile input, and a
  # `javascript:` link in an entry would otherwise be one click from
  # running inside a signed-in session.
  def reader_safe_url(url)
    url.to_s.match?(%r{\Ahttps?://\S+\z}i) ? url.to_s : nil
  end
end
