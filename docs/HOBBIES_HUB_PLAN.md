# HOBBIES_HUB_PLAN.md — the hub is the reader

The Reader shipped as its own destination (`docs/READER.md`, **D-feed-reader**)
with a three-item courtesy card on the Hobbies page. That was backwards. The
river was never meant to be a place you go; it was meant to be **what makes
each hobby different every day**. This plan turns the Hobbies hub into the
reader's home surface — one river per hobby — and demotes `/reader` from a rail
destination to the everything-view you click through to.

The new decision is **D-hobby-feeds**. It reverses one line of D-feed-reader
(items were deliberately not `Sectionable`) and adds one model call per
*subscription* — never per story.

## 1. What changes, in one paragraph

Adding a feed asks the household's model, once, which hobbies it belongs to.
Stories inherit their feed's hobbies at ingest, so every item carries lenses
without a second model call. A feed the model can't pin to a hobby — a world
news site, Hacker News, anything general — is marked **broad**, and its stories
are routed per item by keyword match against each hobby's own vocabulary: no
model, no per-story cost, and an explanation the user can read and edit. The
Hobbies page becomes a grid of hobby cards, each carrying its own three newest
unread underneath the engagement signal it already shows. The rail loses
"Reader" and Hobbies inherits the unread badge.

## 2. Per feed or per story? Both — and the order is the whole design

This was the open question, and the arithmetic answers most of it.

**Per feed** is nearly free. `Feed` is already `Sectionable`, `Feeds::River`
already filters by section, and a subscription is added a handful of times per
household *ever*. One model call per feed is a rounding error, and it is the
only classification that can be *correct by construction*: r/woodworking is
about woodworking in a way no individual post can contradict.

**Per story** is where the cost is. The instance this plan was written against
carried 228 unread items across eight feeds after about two days — call it
100+ items a day, ~3,000 a month. At one model call each that is a real monthly
bill on a hosted provider and an unusable queue on the local models this project
argues for (`CLAUDE.md` → model integration). It also breaks the reader's third
promise — *nothing leaves the box, and it works identically with no API key
configured* — because a hub organized by per-item model calls has no
organization at all on a model-less instance.

But per-feed alone fails exactly where the screenshots show the volume: a
general news feed has no hobby, and its stories have several. Filing the
Guardian under "Reading" would be a lie, and dropping it from the hub would
hide most of the river.

So: **per-feed classification is the backbone, per-story routing is the
exception, and the exception does not use a model.**

| | who decides | when | cost |
|---|---|---|---|
| Focused feed (a subreddit, a channel, a craft blog) | model, once | on subscribe | 1 call, ever |
| Its stories | inherited from the feed | at ingest | 0 |
| Broad feed (news, HN, aggregators) | model marks it broad | on subscribe | (same call) |
| Its stories | keyword match against hobby vocabulary | at ingest | 0 |
| Stories nothing matches | nobody — they stay unfiled | — | 0 |
| *Optional* per-story model pass | model, batched ≤25 | off by default | ~4 calls/day |

The keyword vocabulary is itself AI-generated — once per hobby, not once per
story — and stored on the lens where the user can see and edit it. "Sourdough"
under Baking is a rule you can read, correct, and reason about; a per-item
model verdict is neither.

### Why unfiled stories are a feature

Anything that matches no hobby stays untagged and shows up in one place: the
**Everything else** lane at the foot of the hub, and the `/reader` river. That
lane is the honest home for world news in a Hobbies section, and it is also the
input to the D20-style watcher HOBBIES.md §1.2 already describes: *forty
unfiled stories keep saying "climbing" — want a Climbing hobby?* Agent
proposes, user disposes. Nothing is auto-created.

## 3. Data model

Three small additions. No new tables.

```
Feed        + routing:"inherit"|"per_item"   + classified_at
            (lenses stay ordinary section_taggings — already there)
FeedItem    include Sectionable              ← the D-feed-reader reversal
Section     + keywords (text)                the lens's own vocabulary
```

**`FeedItem` becomes `Sectionable`.** D-feed-reader's reasoning was that "an
item's tags are its feed's tags, so filing happens once, at the subscription" —
true for focused feeds, and the reason inheritance is the default here. It
stops being true the moment one feed's stories belong to different hobbies,
which is the case this plan exists to serve. Tags are **materialized at
ingest** rather than resolved at query time: the hub asks one question per
hobby (`FeedItem.in_section(lens)`), a stray story can be re-filed by hand
without inventing negative tags, and `Feeds::Refresh` already writes each item
once anyway. Retagging a feed enqueues a backfill over its items.

Pruning already caps items at `KEEP_PER_FEED`, so the tagging table grows with
the river rather than without bound.

## 4. Services and jobs

```
Feeds::Classify        one model call: feed → hobby lenses + inherit/per_item
ClassifyFeedJob        runs it after create; re-runnable from the feed row
Hobbies::Vocabulary    one model call: hobby → keywords (on lens create, editable)
Hobbies::Router        no model: item text × lens keywords → lenses
Feeds::Retag           backfill a feed's existing items after a lens change
```

`Feeds::Classify` follows `Notes::Categorize` exactly — a JSON response matched
back through a `Llm::Taxonomy`-style listing restricted to Hobbies' children,
unknown slugs dropped. Its input is the feed's title, description, site URL and
the ten newest entry titles.

**It runs in a job, not the request.** READER.md's two-postures rule
(`docs/READER.md` → "who is waiting") says adding a feed fetches in-request
because the user needs to know the subscription is real; a model call has no
such claim on the user's patience, and a slow provider must not hold the form.
The feed appears immediately, unfiled, and files itself over Turbo when the job
lands — the same broadcast `RefreshFeedJob` already uses.

**With no model configured, everything above is skipped** and the existing
manual lens picker on `/feeds` is the whole story. The hub degrades to "feeds
you filed by hand", which is what it is today. That is the promise-3 test, and
it should have a test with that name.

### Hostile input: the prompt is a stranger's XML

A feed's title and entry titles are written by whoever runs the server, and
this is the first place they reach a model prompt. The threat model is
`docs/EMAIL_PLAN.md`'s, and the mitigation is structural rather than a plea in
the system prompt:

- the model's answer is matched against **existing** lens slugs and anything
  else is dropped — it selects from a closed set, it does not name things;
- the classifier can **never create a lens**, so the worst an injected entry
  achieves is filing its own feed wrongly, which the user can fix in one click;
- entry text is already stripped to plain text at parse time, so no markup
  reaches the prompt;
- the prompt states that feed text is data to classify, never instructions —
  belt to the structural braces.

## 5. The hub

The current page is a grid of hobby cards (identity + engagement) with one
shared "From your feeds" card underneath. The redesign merges them: **the
river moves inside the cards.**

```
Hobbies
  Your hobbies
  ┌─ Baking ────────────┐ ┌─ Guitar ────────────┐ ┌─ Hiking ───────────┐
  │ ● next: class Thu   │ │ ● 2 open tasks      │ │ ● quiet — dive in  │
  │ ─────────────────── │ │ ─────────────────── │ │ ────────────────── │
  │ 3 newest unread     │ │ 3 newest unread     │ │ (no feeds yet)     │
  │ …                   │ │ …                   │ │ + follow a source  │
  │ 12 unread →         │ │ 4 unread →          │ │                    │
  └─────────────────────┘ └─────────────────────┘ └────────────────────┘
  + add a hobby

  Everything else (41)                     Everything →   Manage feeds →
  ─ unfiled stories, newest first, with "file under…" per row
```

Rules that keep this from becoming a second reader:

- **The engagement line stays above the stories.** HOBBIES.md's named trap is
  making consuming the hobby; a card whose top line is "next: class Thursday"
  and whose bottom line is reading material has its priorities visible in its
  layout.
- **Three items, not ten.** The card is a taste and a doorway. Depth is one
  click away in two directions: the hobby's own page, or `/reader`.
- **A hobby with no feeds gets the paste field**, not an empty box — the
  invitation that lives in `_hobby_reader` today, per card.
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

## 6. Waves

Each wave ships something usable on its own, and only wave 2 needs a model.

**W1 — inheritance and the hub (no AI).** `FeedItem` becomes `Sectionable`;
`Feeds::Refresh` tags new items with their feed's lenses; `Feeds::Retag`
backfills on lens change plus a one-off task for existing items. The hub grid
gains per-hobby rivers, the Everything-else lane, and the two through-links;
`Panels::HobbiesLens` gives each hobby page its river; the rail entry moves.
*After W1 the whole redesign works for hand-filed feeds.*

**W2 — `Feeds::Classify`.** The model files a new subscription, marks it
focused or broad, and the feed row grows "Re-file". Tests for the no-model
path and the injection path.

**W3 — `Hobbies::Vocabulary` + `Hobbies::Router`.** Keywords per lens, seeded
by one model call at lens creation and editable on the hobby page; broad feeds'
stories route per item at ingest. The Everything-else lane starts shrinking.

**W4 — optional batched per-story model pass.** Off by default, gated on a
configured model, ≤25 unrouted items per call, only from broad feeds. For
people who want the accuracy and are paying for it anyway.

**W5 — the unfiled watcher.** "Forty unfiled stories keep mentioning
climbing — want a Climbing hobby?" (D20 suggestion, user disposes.)

## 7. Open questions

- **Do non-hobby sections get feeds too?** The plumbing is section-generic —
  a CFPB feed under Money, a Federal Register feed under Rights would work
  unchanged. This plan keeps the surfaces to Hobbies; the classifier is
  restricted to Hobbies' children so it can't file a woodworking blog under
  Health. Widening later is a prompt change and a second panel, not a schema
  change.
- **Should a broad feed's *unmatched* stories be hidden from the hub
  entirely?** Currently they land in Everything else, which risks that lane
  becoming the biggest thing on the page (see the screenshots — world news
  dominates). A cap plus "see all in the reader" is the likely answer.
- **Starter feeds.** The empty-state starter list drafted for this branch
  (`config/starter_feeds.opml`, per-lens folders) becomes much better with a
  classifier in place: the OPML's folders name hobbies, so an imported starter
  list files itself. Sequence it after W2.
