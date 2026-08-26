# STORY_ROUTING_PLAN.md — the broad feed, and the stories inside it

**The model writes the rule; the rule reads the river.**

D-hobby-feeds files *feeds* under hobbies and never files a story. That is
right for the eight feeds a household follows that are about one thing each,
and it is exactly wrong for the two that aren't. The Guardian, Hacker News, a
big subreddit, a Substack somebody writes about four subjects — these land in
Other Interests whole, and the birding stories inside them never reach the
Birding hub. Worse is the alternative the current model is careful to refuse:
if the classifier *did* file that feed under Birding, the Birding river would
fill with the council budget.

This plan is how the stories get out, without buying the per-story model call
that `docs/HOBBIES_HUB_PLAN.md` §2 cut on arithmetic and §8 left as the open
door. The new decision is **D-story-matching**.

## 1. The problem, stated so it can be checked

Two failure shapes, and any answer has to fix the first without causing the
second:

- **The stranded story.** A feed is 5% about a hobby you have. Today those
  stories are unreachable from the hobby — the hub says the hobby is quiet
  while its river sits in the catch-all.
- **The flooded river.** A feed is 5% about a hobby you have. If anything
  files the *feed* under it, the hobby's card and page fill with the other
  95%, which is the thing that makes a hub worth less than no hub.

And three constraints that are not up for renegotiation here, because the
whole reader is built on them:

- **Promise 3** (`docs/READER.md`): it works identically on a box with no API
  key. Any answer that only works with a model configured is not an answer,
  it is a feature for people who have already given up on the premise.
- **The arithmetic** (§2): ~100 items a day on a modest instance, ~3,000 a
  month. A model call per story is a monthly bill on a hosted provider and an
  unusable queue on the local models this project argues for.
- **No enumerating the world** (§2, permanently): a keyword vocabulary *we*
  ship — "sourdough → Baking" — fails silently for every hobby nobody thought
  of, and every user brings one.

## 2. Why the two obvious answers are still wrong, and what is different now

**Classify every story with the model.** Still the wrong bill, and still
breaks promise 3. Batching helps the bill (≤25 titles a call is ~120 calls a
month, not 3,000) and helps nothing else: a no-model instance still gets
nothing, and a local 7B chewing 120 batch calls a month to file stories it
will delete in a week is not what a household's GPU minute is for. Kept as a
contingency in §9, not as the plan.

**Ship a keyword vocabulary.** Still a promise to keep enumerating the world.

What is different is a third thing neither of those is: **the model can write
the vocabulary instead of us, once per hobby, from this user's own reading.**
That inverts the cost curve — calls scale with *hobbies*, which arrive a
handful of times per household ever, rather than with *stories*, which arrive
a hundred a day — and it inverts the failure mode, because a per-user rule
that is wrong is visible, editable, and about one household's Birding rather
than about the concept of birding.

The keyword objection dies with the enumeration. §2's argument was never
"string matching is beneath us"; it was that *we* cannot enumerate the topic
space in advance. A rule authored on demand, for one hobby, by a model that
has read what this user reads, and shown to the user as an editable list of
words, is a different object with a different failure mode:

|                        | shipped vocabulary        | authored watchlist               |
| ---------------------- | ------------------------- | -------------------------------- |
| who enumerates         | us, in advance, for all   | the model, on demand, for one    |
| coverage               | hobbies we thought of     | the hobby the user just named    |
| when it's wrong        | silent, for everyone      | visible on the hobby's own page  |
| how it's fixed         | a release                 | the user deletes a word          |
| cost per story         | 0                         | 0                                |

## 3. The mechanism

### 3.1 A watchlist is what a hobby means to you

One row per user per hobby (`watchlists`): a short list of **terms** that mean
this hobby and a short list of **negatives** that don't. Per user, not per
section, for the same reason feeds are per user (D9): it is learned from
private reading and private corrections, and a shared rule would leak one
household member's rejections into another's river.

A match is: **a term in the title, or two distinct terms anywhere in title +
summary — and no negative anywhere.** Case- and diacritic-insensitive, on word
boundaries. That is the entire rule, and it is one sentence on purpose: it has
to be explainable on the page where the user edits it, because §2's real
lesson is that an unaccountable matcher is worse than no matcher.

Terms are strings, never patterns. No regex, no operators, no SQL — a term is
a word or a short phrase, validated on the way in (§6).

### 3.2 Matching runs at ingest, offline, forever free

`Feeds::Match` runs inside `Feeds::Refresh` over the items it just wrote, for
the user's watchlists, skipping any hobby the item's feed already carries
(that item is already in that river; a match would be redundant). It is a
linear scan over a handful of strings — ~100 items a day × ~10 rules × ~20
terms is nothing, in Ruby, with no model, no index, and no network. No FTS
table: full-text search exists for querying a corpus, and this queries one
item against a rule at the moment the item arrives.

A rule that changes triggers a bounded backfill (`MatchStoriesJob`): the
retained items of the feeds that don't already carry the hobby, newest 30 days
or 500 items, whichever is smaller.

### 3.3 The exception tagging, and the invariant it amends

D-feed-reader says *an item's tags are its feed's tags, so filing happens once,
at the subscription*. This plan amends that in exactly one direction:

> An item's tags are its feed's tags, **plus any exception recorded on the
> item**. Nothing writes an exception in bulk, and no exception ever removes
> what the feed's tags gave.

Exceptions live in their own small table (`feed_item_matches`: item, section,
source), not in `section_taggings`, for three reasons:

- `section_taggings` is the user's filing of **primitives**, and an item is
  not one — it is disposable, pruned on refresh, and becomes a Task or a Note
  when it matters. Widening that table's meaning for a non-primitive is how
  "sections never own tables" starts to rot.
- A match needs `source` (matched by rule / filed by hand), because a rule
  edit may re-evaluate its own matches and must never touch a hand-filed one —
  the same add-only discipline `OtherInterests.claim!` keeps for feeds.
- Matches churn: pruning deletes them, rule edits rewrite them. That churn
  does not belong in the table every section page joins against.

`FeedItem` therefore stays not-`Sectionable`, and every existing query keeps
working unchanged.

### 3.4 The river grows one OR

The hobby river becomes *items from feeds tagged with this hobby, plus items
matched to this hobby*. In `Feeds::River`, that is one OR inside `base`,
**inside the existing `user.feeds` scope** — the reader's one authorization
line ("a river is your own subscriptions") does not move, so a match can never
show an item from a feed the viewer doesn't own, and a section grant can never
widen it. Unread counts, hub cards, the lens page and the everything-view all
inherit it because they all go through `River`.

The catch-all keeps its copy: a broad feed is still unfiled, so its stories
still appear in Other Interests as well as in Birding. Nothing disappears from
where the user last saw it, and the invariant from §3 of the hub plan — every
feed has a hobby or has Other Interests — is about *feeds* and is untouched.

## 4. Where the rule comes from — three doors, and the first one needs no model

1. **By hand.** The hobby page grows a "What counts as Birding" editor: two
   rows of chips, add a word, remove a word. On a no-model instance this is
   the whole feature, and it is a good one — it is Google Reader's smart feed,
   the thing every reader since has quietly dropped. Promise 3 is kept not by
   degrading gracefully but by the manual path being the primary path.
2. **Authored.** When a hobby is created with a model configured,
   `Watchlists::Author` makes **one call**: hobby name, the titles of feeds
   already filed under it, and — the part that matters — the titles the user
   has actually *read* that led here. A hobby spotted by `Hobbies::Spotter`
   (D-hobby-spotting) is born with a draft rule written from the very stories
   that spotted it: the reading that named the hobby becomes the definition of
   it. The result is a draft the user can see and edit, never a black box.
3. **Corrected.** "Not this" on a matched row tombstones the match (a
   rejection that forgets itself is not a correction) and counts against the
   terms that fired. A term the user has rejected three times, and rejected
   more often than they have read, **comes off the list** — deterministic, no
   call. Once corrections accumulate (five, or monthly at most),
   `Watchlists::Author` re-runs with the rejects included and rewrites the
   terms.

   *Changed while building.* The first draft of this line added the fired
   term to the **negatives** instead. That is wrong, and wrong in a way that
   would have quietly destroyed good rules: the word that fires is usually the
   right word inside the wrong story — "warbler" in *Warbler Records signs a
   band* — and negating it kills every real warbler story too. Removing an
   over-broad term narrows the rule; negating a good one guts it. Negatives
   stay something the user types on purpose.

Calls, for a household with ten hobbies: ten at creation, at most ten a month
after that. Against ~3,000 stories a month. That ratio is the plan.

### 4.1 A rule is tested against the river before it ships

The authoring call's output is not trusted, and not because of the model — a
term like "post" or "new" would wreck a river no matter who wrote it. Every
candidate term is run against the last 500 items the user actually has, and
**any term matching more than 20% of them is dropped before the rule is
saved**, with the drop shown in the editor ("'nature' matched half your river,
so it isn't in the list"). It is the cheapest possible evaluation harness and
it runs on the only corpus that matters: this user's.

## 5. What the user sees

- **The hobby page** gains one quiet block: *What counts as Birding* — term
  chips, negative chips, an add field, and one line of receipt ("matched 12
  stories this week"). It sits with the sources, not above the river.
- **A matched row** in any river wears a small tell and, on the expanded row,
  one verb: **Not this**. That is the only new verb the reader gets, and it
  teaches (§4.3) rather than just hiding. The tell has two shapes because the
  row does: the phone's signal line takes a `chip-matched` naming the hobby,
  and the laptop's row — whose signal line is `lg:hidden` — takes a funnel in
  the source column. Both carry the words that fired as their hover title, so
  "why is this Guardian story in Birding" is answerable on the row itself.
- **The counts follow the river.** A hobby's number in the reader's rail, on
  its hub card and on its page counts matched stories too, because a number
  that disagrees with what clicking it shows is worse than no number. A hobby
  with *no feeds of its own* still gets a row, a card and a river when
  something has been matched into it — that stranded case is the whole
  feature, so it cannot be the case that falls through the UI.
- **The hub card** is unchanged, and gets richer for free: a hobby whose feeds
  are quiet but whose subject is in the news now has something to show.
- **Nothing new to triage.** No tray, no "suggested stories" queue, no second
  inbox. Matched stories go into the river they belong to; the correction is
  one click on the row you're already looking at.

## 6. Correct in all cases — the list, and the answer for each

| case | what happens |
| --- | --- |
| **No model configured** | Doors 1 and 3 work in full. Matching is offline; the app behaves identically minus the authoring convenience. |
| **Homonyms** ("bass", "python", "mint") | Title-or-two-terms, negatives, and the 20% corpus test. Then one click on the first wrong row, which writes the negative. |
| **A term that matches everything** | Dropped at authoring (§4.1); if a hand-typed one gets through, or a feed changes what it publishes, the runtime guard suspends that rule *for that feed* once it matches >40% of a week (min. 10 stories) and says so on the hobby page, naming the words. Suspension takes the *unread* matches from that feed with it — they are the flood, nobody has looked at them, and Resume re-derives them. Read ones stay: the app does not take back spent attention. |
| **The user disagrees with the guard** | Resume wins. A resumed feed is remembered, and the guard does not fire on it again — a warning the user has already overruled is nagging, not safety. Changing the words is a new question, and re-opens it. |
| **Hostile feed text** | Terms are validated strings (length, character class, count) — never patterns, never SQL. Read titles from strangers shape an authored draft at worst, and the blast radius is "a word you didn't want appears in an editable list on your own page". The rule can never file a *feed*, create a lens, or leave the box. |
| **One story, several hobbies** | Multi-tagged, like every other lens in the app. |
| **A matched item's feed later gains the hobby** | The match becomes redundant; the OR dedupes it in the query, and the next backfill prunes it. |
| **The hobby is deleted** | Watchlist and matches cascade. The items go back to being ordinary items of their feed. |
| **The item is pruned** | Matches are `dependent: :destroy` on the item; `KEEP_PER_FEED` behaves exactly as it does today. |
| **The hobby is renamed** | Rules attach to the section id, so nothing breaks; the page offers a re-author. |
| **A second household member has the same hobby** | Their own watchlist over their own feeds. Two rules never touch. |
| **Sharing** | Matches live inside `River`'s existing `user.feeds` scope, so a grant can't expose an item from a feed it doesn't already expose. |
| **Non-English feeds** | Matching is unicode-aware and diacritic-insensitive; terms are whatever language the user reads in, because the model wrote them from that user's own titles. |
| **A feed that is 100% one hobby** | Nothing changes — `Feeds::Classify` already files it whole, and matching skips hobbies the feed already carries. |
| **Rule edited badly, river ruined** | Every match is a row with a source; clearing a rule's matched rows is one delete, and hand-filed ones survive it. |

## 7. What this needs

```
watchlists            user, section, terms(json), negatives(json),
                      source(hand|model), refreshed_at, matched_count
                      unique (user_id, section_id)
feed_item_matches     feed_item, section, source(match|hand)
                      unique (feed_item_id, section_id)
```

```
Feeds::Match              item + watchlists → matches (pure Ruby, no model)
Feeds::Watchlists::Author  one model call per hobby → terms, negatives
Feeds::Watchlists::Test    candidate terms vs the user's last 500 items
MatchStoriesJob           backfill after a rule changes
Feeds::River              one OR, inside the existing user scope
FeedItemsController#reject the "Not this" verb
```

Everything else — the hub, the lens pages, the counts, the classifier, the
spotter — is unchanged.

## 8. Waves

All four are built. What each one turned out to be, and the two places the
building changed the design, are in the build log (`bin/status`).

**W1 ✅ — hand-written rules, no AI.** `watchlists`, `feed_item_matches`,
`Feeds::Match` at ingest, the backfill job, the river's OR, the "What counts
as Birding" editor, the matched tell and **Not this**. Ships the whole user
value on a box with no API key, and is the honest floor everything else stands
on.

**W2 ✅ — the model writes the draft.** `Watchlists::Author` at hobby creation
and on demand, seeded from read titles (and from `Hobbies::Spotter`'s evidence
when the hobby was spotted), with the corpus test in front of the save.

**W3 ✅ — the correction loop.** "Not this" writes negatives deterministically;
a monthly re-author folds in confirms and rejects.

**W4 ✅ — the guards and the receipt.** Runtime flood detection with per-feed
suspension, the "this rule matches almost everything" notice, and the weekly
matched count on the hobby page.

W1 is independent and worth shipping alone. W2–W4 each need the one before it.

Two things the build changed, both in §6's direction — the guard has to be
something a person can live with:

- **A correction removes a term; it never writes a negative** (§4.3 above).
- **A resume outranks the guard.** Without that, "Watch it again" started a
  fight the app won every night: the rule was unchanged, so the next refresh
  flooded and re-suspended, and the button looked broken. A suspension the
  user has overruled stays overruled until the words change.

And one thing the build found: `Watchlist#suspend!`/`#resume!` **reload before
editing their lists**. The guard runs in a job while a page may be holding the
same row, and `update!` only writes *changed* attributes — so a stale `[]`
doesn't overwrite a suspension, it silently declines to write anything at all,
which is a harder bug to see than an overwrite.

## 9. Deliberately not doing (and what would change our minds)

- **Per-story model classification**, batched or not. The contingency stays
  where §8 of the hub plan put it: if users report that watchlists miss the
  majority of what they wanted routed, a ≤25-item batched pass, **off by
  default and budget-capped**, becomes the thing that *writes and corrects
  rules* rather than the thing that files stories. Spend calls on the
  classifier, not the classified.
- **Embeddings**, which are the real long-term answer and are not available
  yet: `Llm::Client` speaks chat only, and an `/v1/embeddings` seam is a
  provider-capability question (not every configured endpoint has one). The
  arithmetic is genuinely different — embedding a story is ~1000× cheaper than
  a chat call about it, and free on a local endpoint — so when that seam
  exists, per-hobby centroid similarity over the stories the user *read* can
  replace or back up term matching **without changing anything in §5**. That
  is the point of putting the surface (a visible rule, a matched tell, one
  correcting verb) in front of the mechanism: the mechanism can be swapped and
  the user's mental model survives.
- **A suggested-stories tray.** A second inbox is a worse product than a
  slightly noisy river with a one-click correction.
- **Removing matched items from Other Interests.** The catch-all shows the
  feed; the hobby shows the story. Nothing vanishes from where you left it.
- **Cross-feed duplicate detection.** The same story from two feeds is two
  rows today and stays two rows; it is a separate problem with a separate
  answer (canonical URLs), and conflating it with routing would hide items the
  user is entitled to see twice.
- **Watchlists on non-hobby sections.** The plumbing is section-generic — a
  Money rule over a CFPB feed would work unchanged — but W1–W4 ship for
  Hobbies' children only, the same restriction `Feeds::Classify` already has.
