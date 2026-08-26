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

### Two fetch postures, and the difference is who is waiting

Adding a feed fetches **now**, in the request, on short timeouts: a
subscription that silently fails to exist is worse than a slow form, and
discovery has to answer "is this a feed?" before there is anything to save.

Everything else — "Check now", "Check all", an OPML import, the scheduled
sweep — hands the work to `RefreshFeedJob`. A stranger's server that hangs
must never hold a web worker for the length of a timeout, and the row
updates itself when the job lands: `RefreshFeedJob` broadcasts a Turbo
refresh to the user's `:reader` stream, but only when something actually
changed, since a page-refresh every fifteen minutes for a polite no-op
check is worse than no refresh at all.

### Refresh: idempotent by guid

A publisher who re-lists the same item every hour (many do) can't flood the
river, and an item you have read stays read when it comes back. Existing
rows update in place — a corrected headline should reach you — but the state
attached to an item is the reader's and a fetch never touches it.

### Politeness

This is the one part of the app that makes repeated requests to other
people's servers on a timer, and a self-hosted instance should be
indistinguishable from one person with a browser:

- **Conditional GET.** Every refresh sends back the `ETag` and
  `Last-Modified` the publisher gave us last time, so an unchanged feed
  costs them a header exchange and us no parse at all. Two things are worth
  knowing: the `Last-Modified` value is stored and echoed *raw*, because
  reformatting a date is how a working cache becomes a broken one; and in
  `Web::Fetch`, the `Net::HTTPNotModified` branch has to come **before**
  `Net::HTTPRedirection`, since 304 is a 3xx and Ruby makes the former a
  subclass of the latter — a redirect-first `case` reads every 304 as a
  redirect with a missing `Location`.
- an hourly floor per feed, swept every 15 minutes (`RefreshFeedsJob`),
- exponential backoff after failures, capped at a day,
- a longer interval for a feed nobody has read in a month. "Nobody reads
  it" is `feeds.last_read_at`, denormalized from the items when one is read
  — the sweep asks it as a column rather than counting items once per feed.
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
- an entry's image is validated and stored but not drawn: the list is text
  (see Density below), so a river of forty items makes no request to forty
  strangers' servers at all — when the expanded item lands, that image
  loads lazily and referrer-free,
- outbound links carry `rel="noopener noreferrer nofollow"`.

## The surfaces

### Density is the design (`.reader-line`)

The list *is* the interface here, so the chrome is thin and the rows are
one line: source column, headline, the opening words, the age — Google
Reader's row, at a height where twenty fit on a laptop screen. Three
choices carry it, and they are the reason this page doesn't use the app's
usual card-per-item shape (`docs/DESIGN.md` → Lists):

- **Unread is the emphasised state, read the quiet one**, which inverts the
  app's usual weighting on purpose: in a pile, what you have dealt with
  should recede without disappearing.
- **The verbs are furniture, so they wait for the pointer.** Save / Read /
  Task fade in on hover on a device that can hover (and on focus, for a
  keyboard) — as opacity, never display, so the row can't change height
  under a reader who is scanning. A touch device shows them always.
- **The phone drops the preview, not the headline.** Below `lg` the
  opening words go, the source column folds into the small line that also
  carries the age, the hobby and the verbs, and a row is a headline plus
  one line. The filter rows scroll sideways rather than wrapping into four.

### The pages

- **`/reader`** — the river, newest first. Unread / Saved / Everything,
  narrowed by hobby lens or by feed, with **Mark all read** scoped to
  whatever you are looking at, and the unread count in the rail beside
  "Reader". Per item: save, mark read, open at the source, and **Make a
  task** (prefilled and pre-tagged with the feed's lenses) — the verb that
  makes this a hobby surface rather than a better-groomed reading list.

  **Opening an article marks it read.** Every reader worth using has done
  this since Reader itself; without it "unread" means "not explicitly
  dismissed", which is a different and much less useful thing. The click
  still opens the source; a Stimulus controller rides alongside and asks
  for the same Turbo Stream the Read button would have produced, so there
  is one code path. A modifier or middle click is exempt — that is somebody
  stashing tabs, not reading.

  **A row read from the unread list leaves it**, replaced by a line of its
  own height saying what went, with an **Undo**. Otherwise "unread" is a
  lie and the only way to clear a screen is Mark all read. (Mark all read
  has no undo: it asks first instead.)
- **`/feeds`** — subscriptions: one paste field, per-feed unread counts,
  honest health ("failing — the site answered HTTP 500"), the lens picker
  that files a feed under its hobby, and **OPML import/export**.
- **The Hobbies page** — a "From your feeds" card with the three newest
  unread, or the invitation to follow a first source.

### OPML, in and out

The format every reader since 2000 agrees on, and the only reason a reading
list can survive its reader. An app whose whole argument is that you should
own your things has no business being where a subscription list gets stuck
— the same reasoning as the export archive (D14/M4.2), in the format the
rest of the world can actually read.

OPML's nested outlines are folders, and this app already has folders: hobby
lenses. A lens becomes a folder on the way out; a folder matches a lens by
name on the way in. Import **creates** a missing lens only when the user
ticks the box — silently adding thirty sections to somebody's taxonomy
because their old reader had thirty folders is not an import, it's a mess.
Nothing is fetched during an import: the feeds it names are checked by the
ordinary background refresh afterwards.

## Where this went (D-hobby-feeds)

`docs/HOBBIES_HUB_PLAN.md` folded this surface into the Hobbies hub, and it is
built: one river per hobby card, a full river on each hobby's own page,
`/reader` demoted from a rail destination to the everything-view you click
through to, and feeds filed by the model at subscribe time rather than by hand.
One thing stated above changed, and it is argued in the plan: the reader gained
a model call — one per *subscription*, never per story, so promise 3 survives
intact (an instance with no API key still reads its feeds, it just files them
by hand). Everything else holds, including the line about items not being
`Sectionable`: filing still happens once, at the subscription, and a feed the
model can't place under a hobby lands whole in one called Other Interests.

The empty state gained a starter shelf for the same reason discovery exists —
a blank paste field asks the user to already know what RSS is — and it keeps
promise 1 by being *offered*, never subscribed: a static list in the repo,
nothing fetched to build it, every row a checkbox.

## What it doesn't do yet

- **Full-text extraction / read-here.** Deliberate: the article belongs to
  the site that wrote it, and the reader's job is to get you there.
- **A "what did I miss" digest**, which is a watcher (D20) over the same
  rows rather than anything new.
- **A hard ceiling on unread items.** Pruning only trims *read* ones, so a
  feed nobody opens grows without bound.
- **Folders for the feed filter.** The "Feed · all · A · B · …" line is a
  sideways scroll at thirty feeds; it wants grouping by lens, or a second
  sidebar.
- **Keyboard navigation** (`j`/`k`/`o`), which is the one Reader affordance
  its actual users would notice missing.
- **The expanded item** — Reader opened an entry in place rather than
  sending you off-site. Every row already carries an `image_url` and the
  full summary for the day that lands.
