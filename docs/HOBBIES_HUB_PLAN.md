# HOBBIES_HUB_PLAN.md — the hub is the reader

The Reader shipped as its own destination (`docs/READER.md`, **D-feed-reader**)
with a three-item courtesy card on the Hobbies page. That was backwards. The
river was never meant to be a place you go; it was meant to be **what makes
each hobby different every day**. This plan turns the Hobbies hub into the
reader's home surface — one river per hobby — and demotes `/reader` from a rail
destination to the everything-view you click through to.

The new decision is **D-hobby-feeds**: the model files each *feed* under the
hobbies it belongs to, a feed that matches none lands in **Other Interests**,
and stories are never classified individually.

## 1. What changes, in one paragraph

Adding a feed asks the household's model, once, which of the user's existing
hobbies it belongs to. The answer becomes ordinary section taggings on the
feed, which the reader already understands — so the whole river splits by hobby
with no per-story work at all. A feed that matches no hobby goes to **Other
Interests**, a real lens that gets created the first time it's needed, so
every feed always has a home and no query anywhere needs an "or untagged"
branch. The Hobbies page becomes a grid of hobby cards, each carrying its own
three newest unread underneath the engagement signal it already shows. The rail
loses "Reader" and Hobbies inherits the unread badge.

## 2. Why classification is per feed, and per story is not on the roadmap

**Per feed is nearly free and nearly always right.** `Feed` is already
`Sectionable`, `Feeds::River` already filters by section, and a subscription is
added a handful of times per household *ever*. One model call there is a
rounding error. It is also the only classification that can be right by
construction: r/woodworking is about woodworking in a way no individual post
can contradict.

**Per story is a different product with a different bill.** The instance this
plan was written against carried 228 unread items across eight feeds after
about two days — 100+ items a day, ~3,000 a month. At one model call each that
is a real monthly bill on a hosted provider and an unusable queue on the local
models this project argues for (`CLAUDE.md` → model integration). It would also
break the reader's third promise — *nothing leaves the box, and it works
identically with no API key configured* — because a hub organized by per-item
model calls has no organization at all on a model-less instance.

**And the cheap approximation of it doesn't work.** An earlier draft of this
plan routed broad feeds' stories by keyword match against a per-hobby
vocabulary. It was cut before anything was built: keywords cannot cover the
truly open space of hobbies and feeds that any number of users will bring, and
a matcher that works for "sourdough → Baking" fails silently and
unaccountably for everything nobody thought to enumerate. A vocabulary list is
a promise to keep enumerating the world, which is the kind of promise this
codebase should not make.

So the honest consequence, stated up front: **a broad feed lands in one place,
whole.** The Guardian's world news becomes Other Interests, not fifteen hobbies.
That is correct — a world news feed genuinely isn't a hobby feed — and if the
lane grows uncomfortable, the answers are to unfollow, to make the interest a
hobby, or to revisit per-story classification later with the arithmetic
re-checked (see §8).

## 3. Other Interests

Every feed gets a hobby, or it gets **Other Interests**. There is no third
state, and that is the point: no "untagged" branch in the river query, no
special lane on the hub, no empty-set edge case in the filter row. It is an
ordinary hobby lens — a child section of Hobbies, the same rows D25 already
creates — with three rules on top:

- **Created on demand**, the first time a feed needs it, by slug
  (`other-interests`) rather than by name, so it can't be stolen by a user who
  happens to name a hobby "Other interests".
- **Never offered as a hobby.** It's absent from the capture chips and the
  suggestion lists; the user did not tell us they do this for fun, and the card
  should not pretend otherwise. It sorts last in the grid and reads as the
  catch-all it is.
- **Not a dead end.** A feed sitting here is a feed waiting for the hobby that
  hasn't been created yet, and §4 is how it gets claimed.

## 4. When a hobby appears — and when one goes away

The map is not built once at subscribe time. A household's hobbies arrive over
months, and every new one is a question about **every feed already followed**,
not just the ones parked in Other Interests. Following a lutherie blog under
Guitar and later adding a Woodworking hobby should light up that feed on both
cards; that is the multi-tagging the lens model exists for (a feed is
`Sectionable`, so it takes as many lenses as fit).

`Hobbies::MapFeeds` is the job, and it takes **lens ids**, not one lens: an
OPML import that creates six folders-as-hobbies asks one question about six
lenses rather than six questions. Its rules:

- **It considers every active feed**, whatever it is already tagged with. A
  feed with a hobby can gain another.
- **It only ever adds.** No existing tagging is removed, which is also how a
  hand-made tag is protected without `section_taggings` having to record who
  made it: the model can propose a new home for a feed, never overrule the one
  a human chose.
- **The one removal is mechanical**: a feed that gains a real hobby loses Other
  Interests, because Other Interests means "no hobby" and the two are mutually
  exclusive by definition.
- **It is chunked** (≤40 feeds a call, title + description + host) so a
  household with two hundred subscriptions asks a bounded number of times, and
  **it doesn't run at all** with no model configured, or with no feeds.
- **It is idempotent.** Re-running maps the same feeds to the same lenses; the
  answer is a set of taggings, not an append.

The reverse case has to be handled too, because `sections.section_taggings` is
`dependent: :destroy`: **removing a hobby can leave a feed with no lens at
all.** Those feeds fall back to Other Interests in the same transaction, so the
invariant from §3 — every feed has a hobby or has Other Interests — survives a
deletion. No model call; this is bookkeeping.

Two smaller doors onto the same machinery: per-feed **"Re-file"** on the feeds
list re-asks about one row, and a household that configures a model *after*
following feeds gets one backfill pass over everything unclassified.

## 5. What this needs

Almost nothing, which is the argument for it.

```
Feed   + classified_at:datetime     has the model looked at this yet
       (lenses stay ordinary section_taggings — already there)
```

That is the entire schema change. In particular **`FeedItem` stays exactly as
it is** — not `Sectionable`, no per-item taggings, no ingest-time writes.
D-feed-reader's line holds unchanged: *an item's tags are its feed's tags, so
filing happens once, at the subscription*. It was only ever per-story routing
that wanted to reverse it, and per-story routing is gone.

```
Feeds::Classify        one model call: feed → hobby lenses (or Other Interests)
ClassifyFeedJob        runs it after create; re-runnable per feed ("Re-file")
Hobbies::MapFeeds      new hobby (or hobbies) → which existing feeds join it (§4)
MapFeedsJob            enqueued by hobby creation; also the post-setup backfill
```

`Feeds::Classify` follows `Notes::Categorize` exactly: a JSON response matched
back through a `Llm::Taxonomy`-style listing restricted to Hobbies' children,
unknown slugs dropped, at most two lenses kept. Its input is the feed's title,
description, site URL and the ten newest entry titles — the titles matter,
because a site called "Hackaday" tells the model less than five of its
headlines do.

**It runs in a job, not the request.** READER.md's two-postures rule
(`docs/READER.md` → "who is waiting") says adding a feed fetches in-request
because the user needs to know the subscription is real; a model call has no
such claim on the user's patience, and a slow provider must not hold the form.
The feed appears immediately in Other Interests and re-files itself over Turbo
when the job lands — the same broadcast `RefreshFeedJob` already uses.

**With no model configured, none of this runs.** New feeds land in Other
Interests and the existing manual lens picker on `/feeds` is the whole story;
a user who files by hand never sees a difference. That is the promise-3 test,
and it should have a test with that name.

### Hostile input: the prompt is a stranger's XML

A feed's title and entry titles are written by whoever runs the server, and
this is the first place they reach a model prompt. The threat model is
`docs/EMAIL_PLAN.md`'s, and the mitigation is structural rather than a plea in
the system prompt:

- the model's answer is matched against **existing** lens slugs and anything
  else is dropped — it selects from a closed set, it does not name things;
- the classifier can **never create a lens** (Other Interests is created by our
  code, not by a model answer), so the worst an injected entry achieves is
  filing its own feed wrongly, which the user fixes in one click;
- entry text is already stripped to plain text at parse time, so no markup
  reaches the prompt;
- the prompt states that feed text is data to classify, never instructions —
  belt to the structural braces.

## 6. The hub

The current page is a grid of hobby cards (identity + engagement) with one
shared "From your feeds" card underneath. The redesign merges them: **the
river moves inside the cards.**

```
Hobbies
  Your hobbies                            [ Everything · 41 ]  Manage feeds →
  ┌─ Baking ─────Sep 3 ─┐ ┌─ Guitar ────2 tasks ┐ ┌─ Other Int. no hobby┐
  │ ─────────────────── │ │ ─────────────────── │ │ ────────────────── │
  │ 3 newest unread     │ │ 3 newest unread     │ │ 3 newest unread    │
  │ …                   │ │ …                   │ │ …                  │
  │ 12 unread →         │ │ 4 unread →          │ │ 41 → File these →  │
  └─────────────────────┘ └─────────────────────┘ └────────────────────┘
  ┌─ Explore other hobbies ──────────────┐ ┌─ Add another hobby ───────┐
  │ Hiking · Drawing · Gaming · Swimming │ │ [ name a hobby ]   [Add]  │
  └──────────────────────────────────────┘ └───────────────────────────┘
```

Rules that keep this from becoming a second reader:

- **What you do stays above what you read**, but on the *name's own line*.
  HOBBIES.md's named trap is making consuming the hobby, so the signal keeps
  its place at the top of the card — it just stopped costing a row of height
  to say it. One thing, most actionable first (a date beats a count, because
  a date is a commitment and a count is a pile), with the event's own title
  on hover. A hobby with nothing on says nothing: silence is shorter than
  "nothing planned yet" and means the same. The full picture — every event,
  task and project — is one click away on the lens page, which is what a hub
  is *for*.
- **Three items, not ten.** The card is a taste and a doorway. Depth is one
  click away in two directions: the hobby's own page, or `/reader`.
- **A card is for a hobby with something in it.** A household names hobbies
  far faster than it fills them, so most of a real instance's grid was cards
  saying "nothing planned yet" — which buried the two or three that had
  something to show. Those become one line each in a single **Explore other
  hobbies** card: still a doorway, at the size a doorway needs. "Something in
  it" means feeds or engagement, never *unread*, because a card that vanished
  the moment you finished reading it would rearrange the grid as you use it.
- **No paste field on the hub.** Following a source belongs on a hobby's own
  page, where somebody has already decided to spend time on it; here it was
  nine copies of the same form.
- **`.reader-line` density is reused**, not reinvented. The rows are the same
  partial at a smaller item count.

### Filtering to one hobby

The hobby lens page (`/sections/<slug>`) grows a full river for that hobby
above its Act/Attend/Browse zones. D37 forbids editing `SectionsController`,
`sections/show.html.erb` or `SectionsHelper` for a section feature, and
`Sections::Panel.for` resolves `Sections::Panels::<Slug>` — which never matches
a user-created lens. One narrow change to `Panel.for` fixes that generally:
fall back to `Sections::Panels::<Parent>Lens` for a child section. Hobbies then
registers `Sections::Panels::HobbiesLens`, and People's groups get the same
seam for free later.

### The rail

`Reader` leaves the sidebar; its unread badge moves to `Hobbies`. `/reader`,
`/feeds` and every feed route stay exactly as they are — the everything-view is
still the dense chronological river, still filterable by hobby and feed, and it
is now reached from the hub, the hobby pages, and bookmarks. Nothing is
deleted; one nav entry is.

## 7. Waves

All five are built. What each one turned out to be, and the two places the
building changed the design, are in the build log (`bin/status`).

**W1 ✅ — the hub (no AI).** Per-hobby rivers in the hobby cards, the Other
Interests lens and its card, `Panels::HobbiesLens` for per-hobby pages, the two
through-links, the rail change. Every existing feed gets filed into Other
Interests by a one-off backfill unless the user already tagged it. *After W1
the whole redesign works, filed by hand.*

**W2 ✅ — `Feeds::Classify`.** The model files a new subscription on add; the feed
row grows "Re-file"; `classified_at` distinguishes "the model passed on this"
from "the model has never seen it". Tests for the no-model path and the
injection path.

**W3 ✅ — `Hobbies::MapFeeds` (§4).** Creating a hobby maps the existing feeds
onto it — from the capture chips, the add tile, and an OPML import's folders,
all through `Hobbies::Lens.find_or_create!` so there is one seam rather than
three. Plus the deletion fallback, per-feed "Re-file", and the backfill for a
household that configures its model late.

**W4 ✅ — starter feeds in the empty state (§7.1).** A hand-curated list of
long-lived, publisher-run feeds offered — never subscribed — to a household
with an empty reader.

**W5 ✅ — the watcher.** When Other Interests keeps filling with feeds about the
same thing, suggest the hobby (D20: agent proposes, user disposes). This is
the honest version of the "we noticed you're into X" feature, and it operates
on feeds — a handful of rows — rather than on the story firehose.

W3, W4 and W5 are independent of each other once W2 exists; the order above is
a guess at value, not a dependency chain.

Two things the build changed. **`Sections::Panel#partial` now derives from the
panel class** rather than the section slug — the same string for every seeded
panel, and the only thing that can serve many sections at once, which a lens
panel must. And **W5 needed a model call**, making it the second watcher off
the SQL-only leash after `job_scout`: "these four feeds are all about birding"
is not a question SQL can answer, and the answer that tried — keyword matching
— is the one §2 cut. It stays cheap and rare by reading a handful of *feeds*
rather than the story firehose, and its write surface is a suggestion whose
accept opens Start-a-hobby: the lens is created by the tool the user ran, never
by a watcher and never by a model's answer.

### 7.1 Starter feeds, and the promise they must not break

A hub whose empty state is a blank paste field asks the user to already know
what RSS is. A short starter list fixes that, and READER.md's first promise —
*every source is one the user chose; no recommendations from strangers, no
discovery feed* — draws the line it has to respect:

- **Offered, never subscribed.** Nothing is followed at signup or in the FTUE.
  The list is checkboxes; a feed is followed because somebody ticked it. A
  stocked shelf, not a recommendation engine.
- **Shown only when the reader is empty**, and reachable afterwards from
  `/feeds` for somebody who wants a second look. It never appears above a
  river that has anything in it.
- **Static, offline, in the repo.** `config/starter_feeds.opml`, ordinary
  OPML with the outline folders naming common hobbies. Nothing is fetched to
  build the list, nothing is personalized, nothing is scored, and a
  self-hoster can edit or delete the file.
- **Ticked feeds go through `Feeds::Opml.import`**, which already skips
  fetching, matches folders to existing lenses by name, dedupes by URL and
  enqueues `RefreshFeedJob`. So the starter list needs no new fetch posture
  and no new parse path — and with W2 in place, anything whose folder doesn't
  match a hobby the user has still gets filed by the classifier rather than
  landing in Other Interests by default.

What earns a place on the list, in priority order: a **publisher-run URL**
(never an aggregator or a FeedBurner proxy — that single point of failure is
the Google Reader story this whole feature answers), no account or paywall, a
decade of URL stability, politeness to poll, and coverage spread across the
kinds of things people have hobbies about rather than a news firehose. A
starter that fails its first refresh is dropped from the list rather than left
as a red row in a brand-new account.

**Breadth, and what it cost.** The shelf shipped with fourteen feeds across
nine topics, which is a shelf that answers "do you like technology or world
news?" — for anybody whose hobby is birding or chess or brewing, an empty
reader offering nine topics is still an empty reader. It now carries ~150
feeds across ~48 topics. Breadth changes the shape of the thing twice over:

- **The shelf is browsed, not read.** Every topic renders as a closed
  `<details>` (no JS, the fold the circle cards already use) in two or three
  columns, so what somebody meets is a page of topic names — the wall of
  checkboxes only appears inside the topic they opened. Ticking works whether
  or not the folds are open, because the inputs are in the DOM either way.
- **Hand-verification stops scaling, so it's CI's job.**
  `script/check_starter_feeds.rb` fetches every row through the ordinary
  `Web::Fetch` + `Feeds::Parse` path and exits non-zero on anything that
  isn't a feed; `.github/workflows/starter-feeds.yml` runs it weekly and on
  any PR touching the file. It retries each failure once (one timeout in a
  hundred and fifty fetches is weather) and never runs two fetches at the
  same host at once — this list multiplies by every self-hoster who ticks it.
  It is the only job in CI that talks to the open web, which is why it is
  path-filtered off every unrelated PR.

The structural rules that don't need the network — https only, no
redirector hosts, unique URLs, every row foldered, and floors on how many
topics and feeds the shelf carries — stay in `Feeds::StartersTest`, where
they run on every PR for free.

## 8. Deliberately not doing (and what would change our minds)

- **Per-story classification.** Cut for the reasons in §2. What would revisit
  it: a local-model story where a small classifier runs on-box for free, or a
  batched pass (≤25 items a call, off by default) if users report that broad
  feeds are the majority of their river and Other Interests has become a
  second inbox. Neither is speculative infrastructure worth building now.
- **Keyword/vocabulary routing.** Cut permanently. Enumerating the topic space
  is a promise we can't keep.
- **Feeds on non-hobby sections.** The plumbing is section-generic — a CFPB
  feed under Money would work unchanged — but the classifier is restricted to
  Hobbies' children so a woodworking blog can't land under Health. Widening
  later is a prompt change and a second panel, not a schema change.
- **Auto-subscribing anything.** The starter list in §7.1 is offered, never
  applied. A default subscription would make the first river something the app
  chose, which is the thing READER.md's first promise exists to refuse.
