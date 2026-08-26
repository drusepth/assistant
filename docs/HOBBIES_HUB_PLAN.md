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
re-checked (see §7).

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
- **Not a dead end.** Creating a new hobby re-asks the model about the feeds
  sitting in Other Interests — one batched call, only those feeds, only against
  the new lens — so following a guitar blog before you have a Guitar hobby
  fixes itself the moment you add one. Per-feed "Re-file" does the same for
  one row on demand.

## 4. What this needs

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
ClassifyFeedJob        runs it after create; re-runnable per feed
Hobbies::Reclassify    batched re-ask for Other Interests feeds when a hobby appears
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
  ┌─ Other Interests ───┐                  Everything →   Manage feeds →
  │ 41 unread           │
  └─────────────────────┘
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

**W1 — the hub (no AI).** Per-hobby rivers in the hobby cards, the Other
Interests lens and its card, `Panels::HobbiesLens` for per-hobby pages, the two
through-links, the rail change. Every existing feed gets filed into Other
Interests by a one-off backfill unless the user already tagged it. *After W1
the whole redesign works, filed by hand.*

**W2 — `Feeds::Classify`.** The model files a new subscription on add; the feed
row grows "Re-file"; `classified_at` distinguishes "the model passed on this"
from "the model has never seen it". Tests for the no-model path and the
injection path.

**W3 — `Hobbies::Reclassify`.** Adding a hobby re-asks about the feeds in Other
Interests, in one batched call.

**W4 — the watcher.** When Other Interests keeps filling with feeds about the
same thing, suggest the hobby (D20: agent proposes, user disposes). This is
the honest version of the "we noticed you're into X" feature, and it operates
on feeds — a handful of rows — rather than on the story firehose.

## 7. Deliberately not doing (and what would change our minds)

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
- **Starter feeds.** The empty-state starter list drafted for this branch
  (`config/starter_feeds.opml`, per-lens folders) gets better once W2 exists:
  the OPML's folders name hobbies, and anything unmatched has a home. Sequence
  it after W2.
