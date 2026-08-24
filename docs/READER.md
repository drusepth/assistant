# READER.md

The feed reader (**D-feed-reader**) — Google Reader's shape, rebuilt on a
box the household owns, with the one thing Reader never had: it knows what
you're into. Built as the daily surface of the Hobbies section
(`docs/HOBBIES.md` §3), reachable from the rail as **Reader**.

## Why this is in an AI life assistant at all

The mission argument is in `docs/VISION.md`, and Hobbies is where it gets
sharpest: the target user's relationship with their own interests is
mediated by feeds optimized to keep them scrolling *about* a hobby instead
of doing it. Google Reader was the last mass-market piece of software where
the reading list was chosen by the reader — and it was switched off, from
outside, by a company that owed nobody an explanation. That is the feudal
pattern the whole project exists to answer, in miniature.

So the counter-move is the same as everywhere else here: owned sources,
owned state, an ordering made of the user's own words, and every path out
of the river ending in *doing* something rather than in more reading.

Three properties, stated as promises the code has to keep:

1. **Every source is one the user chose.** No recommendations from
   strangers, no discovery feed, no "you might also like" from an index we
   don't own.
2. **The ranking is explainable and optional.** It is arithmetic over the
   user's own hobbies and votes, it says why it lifted something, and
   *Newest* turns it off in one click.
3. **Nothing leaves the box.** No model call, no third-party ranking
   service, no telemetry. The reader works identically on an instance with
   no API key configured at all — it is Organize-mode infrastructure that
   happens to be fed from outside.

## The shape

```
Feed  (a subscription: url, title, lenses, health)   Visible + Sectionable
  └── FeedItem  (an entry + this reader's state: read_at, saved_at, vote, relevance)
```

`Feed` is a primitive like any other — owned by one user, taggable by
section — and the hobby lenses it carries (D25) are what make the river's
ranking personal rather than generic. `FeedItem` is deliberately *not*
Sectionable: an item's tags are its feed's tags, so filing happens once, at
the subscription, and the hobby filter is a join rather than a per-item
write. Items are disposable; the ones worth keeping become saves, Tasks or
Notes.

Subscriptions are per-user. Read state is personal, so a shared row would
mean sharing whether you'd read something — see **Q-feed-sharing** for what
would change that.

## The pipeline

| Step | Where | What it does |
|---|---|---|
| Discover | `Feeds::Discover` | Paste anything → the feed behind it |
| Parse | `Feeds::Parse` | RSS 2.0 / RDF / Atom / JSON Feed → one `Entry` shape |
| Refresh | `Feeds::Refresh` | Fetch, fold in by guid, score, prune |
| Score | `Feeds::Interest` | The user's words → a relevance in -1..1 |
| Rank | `Feeds::Rank` | relevance + age → the river's order |
| Read | `Feeds::River` | Filters + paging, the one authorization line |

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

### Ranking: half a day of freshness

```
score = relevance × 12h − hours_old   (+3h if saved)
```

Everything is in hours, which is what makes the ordering explainable in one
sentence: **a perfect match is worth half a day of freshness.** A strong
match leads the river this morning and is behind this afternoon's news by
tonight. That is the property a reader opened twice a day needs, and the
reason the ranking isn't a decay curve multiplied by affinity — that shape
ties "how much does interest matter" to "how fast does news age", and the
two are separate questions.

`relevance` (-1..1) is `Feeds::Interest`, built from three sources, all of
them the user's own words:

- **hobby lenses** — the names they chose for what they do (weight 1.0),
  plus a flat lens bonus for any item from a feed filed under a hobby (an
  item from the Guitar feed is about guitar whatever its headline says),
- **what they keep under those lenses** — titles of hobby-tagged notes,
  goals, tasks and events (0.3), which is the profile-note idea from
  `docs/HOBBIES.md` §1 read as vocabulary rather than as prose,
- **votes cast in the reader** (+0.5 / −0.9). Dislike learns faster than
  like, because a river's failure mode is one loud feed drowning the rest
  and the user has already told us.

Scores are squashed through `tanh`, so a headline that hits six weak words
can't outrank one that hits the hobby itself. A downvoted-flavoured item
**sinks rather than disappearing** — the reader never silently hides a
source somebody subscribed to.

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

- **`/reader`** — the river. Unread / Saved / Everything × Interesting /
  Newest, narrowed by hobby lens or by feed. Per item: vote, save, mark
  read, open at the source, and **Make a task** (prefilled and pre-tagged
  with the feed's lenses) — the verb that makes this a hobby surface rather
  than a better-groomed reading list.
- **`/feeds`** — subscriptions: one paste field, per-feed unread counts,
  honest health ("Last check failed — the site answered HTTP 500"), and the
  lens picker that makes the ranking yours.
- **The Hobbies page** — a "From your feeds" card with the three the
  ranking would lead with, or the invitation to follow a first source.

## What it doesn't do yet

- **Conditional GET** (`ETag` / `If-Modified-Since`). The interval floor is
  most of the politeness; this is the rest of it, and it needs `Web::Fetch`
  to hand back response headers.
- **OPML import/export.** The obvious next thing for anybody arriving from
  another reader, and export belongs in the takeable-copy manifest too.
- **Full-text extraction / read-here.** Deliberate for now: the article
  belongs to the site that wrote it, and the reader's job is to get you
  there.
- **A "what did I miss" digest**, which is a watcher (D20) over the same
  rows rather than anything new — and the natural home for the LLM garnish
  this feature deliberately does without today.
- **Sharing a subscription inside the household** — Q-feed-sharing.
