<!-- decided -->
**D-feed-reader. The reader: a chronological river over the feeds behind the user's hobbies — no ranking, no scores, no votes.**
Two new tables — `feeds` (a subscription: `Visible` + `Sectionable`, so a
feed is filed under the hobby lenses it belongs to, D25) and `feed_items`
(an entry, carrying the reader's own read/saved state). The reading list
imports and exports as **OPML**, where a hobby lens is a folder: a list
that can't leave its reader isn't owned, whatever the storage says. Items are
deliberately *not* Sectionable: an item's tags are its feed's tags, so
filing happens once, at the subscription, and the hobby filter is a join.
Paste any address and `Feeds::Discover` finds the feed behind it
(autodiscovery tags, then the conventional paths, with subreddits/YouTube
channels/GitHub repos rewritten to their documented feed URLs);
`Feeds::Parse` normalizes RSS 2.0, RDF, Atom and JSON Feed into one shape;
`Feeds::Refresh` folds entries in idempotently by guid, so a re-listed item
stays read.

**The order is chronological, and that is the decision.** The first build of
this had a hobby-aware relevance score, up/down votes that trained it, and a
decay curve — and it was wrong for what this is. Every source here was
chosen by hand, one at a time, so there is nothing to sift: ranking a list
you curated yourself only makes it less predictable, and a vote is a rating
mechanic that needs an audience. This is one person's reading list. The
verbs are therefore *seen* and *kept* — read/unread, save — plus filters
(hobby, feed, unread/saved) and "Make a task", which is the one that matters
for the section: the river should end in doing something, not in a
better-groomed reading list.

Why this belongs in Hobbies: docs/HOBBIES.md §3 split "surface interesting
content" on the Q9 line and deferred the live half. This is the honest
resolution of that half — the user picks the sources, so the app needs no
crawler, no third-party index and no capability it doesn't have. It is
`Organize`-mode infrastructure that happens to be fed from outside, and it
works on an instance with no model configured at all: there is no LLM
anywhere in this feature.

Politeness is a design constraint, since this is the one part of the app
that polls strangers' servers on a timer: conditional GET (the publisher's
own `ETag`/`Last-Modified`, echoed raw), an hourly floor per feed,
exponential backoff on failure (capped at a day), a longer interval for a
feed nobody reads any more, and a read-item cap per feed — the river is not
an archive. Only *adding* a feed fetches in the request; every other check
is a job, because a stranger's server that hangs must never hold a web
worker. Feed bodies are hostile input from strangers: entities are
never expanded, summaries are stripped to text at parse time (nothing
downstream holds a string it could be tempted to call `html_safe` on),
item links and images are refused unless `http(s)` (in the parser, so an
entry is safe by construction), and every fetch goes through `Web::Fetch`'s
SSRF guard.
