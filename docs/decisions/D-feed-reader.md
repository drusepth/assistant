<!-- decided -->
**D-feed-reader. The reader: a Google-Reader-shaped feed river over user-chosen feeds, ranked by hobby-aware relevance computed on the user's own words.**
Two new tables — `feeds` (a subscription: `Visible` + `Sectionable`, so a
feed is filed under the hobby lenses it belongs to, D25) and `feed_items`
(an entry, carrying the reader's own read/saved/vote state). Items are
deliberately *not* Sectionable: an item's tags are its feed's tags, so
filing happens once, at the subscription. Paste any address and
`Feeds::Discover` finds the feed behind it (autodiscovery tags, then the
conventional paths, with subreddits/YouTube channels/GitHub repos rewritten
to their documented feed URLs); `Feeds::Parse` normalizes RSS 2.0, RDF,
Atom and JSON Feed into one shape; `Feeds::Refresh` folds entries in
idempotently by guid, so a re-listed item stays read.

The ranking is the point, and it is deliberately small: `score =
relevance × 12h − hours_old`, where relevance (-1..1) comes from
`Feeds::Interest` — the hobby lenses the user created, the titles of what
they keep under those lenses, and the votes they cast in the reader
itself. **A perfect match is worth half a day of freshness**: a lift, never
a permanent seat, which is the failure mode of ranking purely on affinity.
No model call is involved (the reader has to work on an instance with no
API key at all), nothing leaves the box, every lift is explainable in the
user's own nouns ("Because you're into Woodworking"), a downvote sinks an
item rather than hiding it, and "Newest" turns the whole thing off in one
click.

Why this belongs in Hobbies rather than being a generic app: docs/HOBBIES.md
§3 split "surface interesting content" on the Q9 line and deferred the live
half. This is the honest resolution of that half — the user picks the
sources, so the app needs no crawler, no third-party index and no
capability it doesn't have. The reader is `Organize`-mode infrastructure
that happens to be fed from outside, and its per-item verbs end in *doing*
("Make a task"), which is the section's whole discipline.

Politeness is a design constraint, since this is the one part of the app
that polls strangers' servers on a timer: an hourly floor per feed,
exponential backoff on failure (capped at a day), a longer interval for a
feed nobody reads any more, and a read-item cap per feed — the river is not
an archive. Feed bodies are hostile input from strangers: entities are
never expanded, summaries are stripped to text at parse time (nothing
downstream holds a string it could be tempted to call `html_safe` on),
item links and images are refused unless `http(s)`, images load lazily with
no referrer, and every fetch goes through `Web::Fetch`'s SSRF guard.
