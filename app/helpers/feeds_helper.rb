# Helpers for the subscription surfaces (D-feed-reader, D-feed-explore).
# The reader's own row helpers live in ReaderHelper; these are about feeds
# you don't have yet.
module FeedsHelper
  # A starter row points at a stranger's site: new tab, no window handle
  # back into the app, no referrer telling them which page sent you. Same
  # posture the reader takes on an item's link, for the same reason. The
  # feed URL is the fallback, because a row with nowhere to look is worse
  # than a row that opens XML.
  def shelf_site_url(entry)
    reader_safe_url(entry.site.presence || entry.url)
  end
end
