# READER.md

The feed reader (**D-feed-reader**) — Google Reader's shape, rebuilt on a
box the household owns: the feeds behind your hobbies, in one chronological
river. Built as the daily surface of the Hobbies section
(`docs/HOBBIES.md` §3), reachable from the rail as **Reader**.

## Why this is in an AI life assistant at all

The mission argument is in `docs/VISION.md`, and Hobbies is where it gets
sharpest: the target user's relationship with their own interests is
mediated by feeds optimized to keep them scrolling *about* a hobby instead
of doing it. Google Reader was the last mass-market piece of software where
the reading list was chosen by the reader — and it was switched off, from
outside, by a company that owed nobody an explanation. That is the feudal
pattern the whole project exists to answer, in miniature.

So: owned sources, owned state, the publisher's own order, and a path out of
the river that ends in *doing* something rather than in more reading.

Three properties, stated as promises the code has to keep:

1. **Every source is one the user chose.** No recommendations from
   strangers, no discovery feed, no "you might also like".
2. **Nothing reorders what you follow.** Newest first, across all your
   feeds. No score, no relevance, no engagement weighting — see below.
3. **Nothing leaves the box.** No model call, no third-party service, no
   telemetry. The reader works identically on an instance with no API key
   configured at all — it is Organize-mode infrastructure that happens to
   be fed from outside.

### The ranking that isn't there

The first build of this had a hobby-aware relevance score, up/down votes
that trained it, and a decay curve balancing the two. It was cut, and the
reasoning is worth keeping because it generalizes to the rest of the app:

- **A curated list needs no sifting.** These sources were added one at a
  time, by hand, by the person reading them. Ranking is what you reach for
  when the firehose is somebody else's; here it only makes the order
  unpredictable, which is the property the feeds this replaces are made of.
- **A vote is a rating mechanic, and ratings need an audience.** One person
  reading their own subscriptions has nobody to signal to. "Was this good?"
  is a question with no consumer — the only honest signals are *did you read
  it* and *did you keep it*, and both are already buttons.
- **Chronological is explainable without a paragraph.** Anything that needs
  a docs section to justify its ordering has already lost an argument with
  a river.

What survives from that pass is the part that was never about ranking: feeds
are **filed under hobby lenses**, so the river filters by hobby. That is a
lens over the same shared pool, exactly as everywhere else in the app.

## The shape

```
Feed  (a subscription: url, title, lenses, health)   Visible + Sectionable
  └── FeedItem  (an entry + this reader's state: read_at, saved_at)
```

`Feed` is a primitive like any other — owned by one user, taggable by
section — and the hobby lenses it carries (D25) are what the river's filter
reads. `FeedItem` is deliberately *not* Sectionable: an item's tags are its
feed's tags, so filing happens once, at the subscription. Items are
disposable; the ones worth keeping become saves, Tasks or Notes.

## The pipeline

| Step | Where | What it does |
|---|---|---|
| Discover | `Feeds::Discover` | Paste anything → the feed behind it |
| Parse | `Feeds::Parse` | RSS 2.0 / RDF / Atom / JSON Feed → one `Entry` shape |
| Refresh | `Feeds::Refresh` | Fetch, fold in by guid, prune |
| Read | `Feeds::River` | Filters + paging + the one authorization line |

### Discovery: paste anything

Google Reader's one piece of real magic was that you handed it the address
of a site you liked and it worked out the rest. Asking somebody to find the
orange XML icon is exactly the friction that made feeds feel like a
hobbyist's format. Four passes, cheapest first:

1. **Rewrite** the addresses whose feed is mechanical — a subreddit
   (`/r/x` → `/r/x/.rss`), a YouTube channel, a GitHub repo's releases.
   Conveniences, not integrations: each is a documented public feed path
   and the result goes through the same fetch-and-parse as anything else.
2. **Try the URL itself** — most pastes are already a feed.
3. **Read the page's `<link rel="alternate">`** autodiscovery tags.
4. **Guess** the conventional paths (`/feed`, `/feed.xml`, `/rss`, …), at
   most four.

Every fetch goes through `Web::Fetch`, so the SSRF guard, size cap and
redirect cap all apply. `Web::Fetch.raw` was added for pass 3 — finding a
`<link>` means reading the markup that the text extraction exists to throw
away. Anything that hands a page to a *model* still goes through `.text`.

### Refresh: idempotent by guid

A publisher who re-lists the same item every hour (many do) can't flood the
river, and an item you have read stays read when it comes back. Existing
rows update in place — a corrected headline should reach you — but the state
attached to an item is the reader's and a fetch never touches it.

### Politeness

This is the one part of the app that makes repeated requests to other
people's servers on a timer, and a self-hosted instance should be
indistinguishable from one person with a browser:

- an hourly floor per feed, swept every 15 minutes (`RefreshFeedsJob`),
- exponential backoff after failures, capped at a day,
- a longer interval for a feed nobody has read in a month,
- a read-item cap per feed — the river is not an archive. Saved and unread
  items are never pruned.

### Hostile input

A feed body is a stranger's XML rendered in a signed-in session, so the
threat model is the same one `docs/EMAIL_PLAN.md` names for mail:

- external entities are never expanded and no DTD is fetched,
- summaries are stripped to plain text at parse time, so nothing downstream
  holds a string it could be tempted to call `html_safe` on,
- item links and image sources are refused unless `http(s)` — a
  `javascript:` link in an entry would otherwise be one click from running
  inside the session,
- images load lazily and with no referrer: a river of forty items doesn't
  announce itself to forty servers before anybody scrolls,
- outbound links carry `rel="noopener noreferrer nofollow"`.

## The surfaces

- **`/reader`** — the river, newest first. Unread / Saved / Everything,
  narrowed by hobby lens or by feed, with **Mark all read** scoped to
  whatever you are looking at. Per item: save, mark read, open at the
  source, and **Make a task** (prefilled and pre-tagged with the feed's
  lenses) — the verb that makes this a hobby surface rather than a
  better-groomed reading list.
- **`/feeds`** — subscriptions: one paste field, per-feed unread counts,
  honest health ("Last check failed — the site answered HTTP 500"), and the
  lens picker that files a feed under its hobby.
- **The Hobbies page** — a "From your feeds" card with the three newest
  unread, or the invitation to follow a first source.

## What it doesn't do yet

- **Conditional GET** (`ETag` / `If-Modified-Since`). The interval floor is
  most of the politeness; this is the rest of it, and it needs `Web::Fetch`
  to hand back response headers.
- **OPML import/export.** The obvious next thing for anybody arriving from
  another reader. Subscriptions already ride the JSON export (M4.2).
- **Full-text extraction / read-here.** Deliberate: the article belongs to
  the site that wrote it, and the reader's job is to get you there.
- **A "what did I miss" digest**, which is a watcher (D20) over the same
  rows rather than anything new.
- **Keyboard navigation** (`j`/`k`/`o`), which is the one Reader affordance
  its actual users would notice missing.
