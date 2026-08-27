# STORY_ROUTING_PLAN.md — the broad feed, and the stories inside it

**The model reads the stories. Nothing matches a word.**

D-hobby-feeds files *feeds* under hobbies and never files a story. That is
right for the eight feeds a household follows that are about one thing each,
and it is exactly wrong for the two that aren't. The Guardian, Hacker News, a
big subreddit, a Substack somebody writes about four subjects — these land in
Other Interests whole, and the birding stories inside them never reach the
Birding hub. Worse is the alternative the current model is careful to refuse:
if the classifier *did* file that feed under Birding, the Birding river would
fill with the council budget.

This plan is how the stories get out. The decision is **D-story-matching**,
and its answer is the same one the rest of the app gives to every "which of
these belongs where" question: **ask the model.** Per-story classification,
batched, over the only stories that need it.

> **This plan was built twice.** The first version routed stories by matching
> per-hobby *term lists* — words the model wrote once and the user could edit
> — offline at ingest, for no marginal cost. It worked, it shipped, and it was
> wrong: a word list is a rule about an open subject, and keyword matching is
> a worse classifier than the classifier we already have. The whole mechanism
> was replaced by the one described here (D-no-keyword-logic). What the first
> version got right is kept: the exception table, the river's one OR, the
> "Not this" verb, and the rule that the user must be able to see why a story
> is in their hobby. §10 is the honest record of what changed and why.

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

- **Promise 3** (`docs/READER.md`): the reader works on a box with no API key.
  Routing is the one part that doesn't — see §2 — so nothing else may depend
  on it: every feed still lands somewhere, every river still fills, and the
  only thing a model-less instance loses is stories moving *between* rivers.
- **The arithmetic** (§2): ~100 items a day on a modest instance, ~3,000 a
  month. A call per story is a real bill; a call per story *that needs one* is
  not. The difference is what §2 is about.
- **No enumerating the world** (§2, permanently): a vocabulary of words for a
  subject — whoever writes it — fails silently for everything nobody thought
  of. This is now the general rule, not a rule about this feature
  (D-no-keyword-logic).

## 2. Why this is a model call, and what makes it affordable

D-hobby-feeds §2 cut per-story classification on arithmetic: ~100 items a day,
~3,000 a month, one call each. That arithmetic was right about *classifying
every story* and wrong about the conclusion, because almost none of those
stories need classifying:

- **Most feeds are about one thing.** `Feeds::Classify` already asks the model,
  once per subscription, which hobbies a feed belongs to. It now asks a second
  question in the same call — **is this feed about one subject, or many?** A
  focused feed's stories inherit its hobbies and are never read individually.
- **So the firehose is a trickle.** Only broad feeds' stories are read. A
  household with two broad feeds publishing 60 stories a day, batched twenty
  to a call, spends ~3 calls a day — and a household with none spends nothing.
- **Each story is read once.** `feed_items.routed_at` is stamped whether or not
  anything was routed, so no story is ever paid for twice.
- **A run is capped.** `MAX_PER_RUN` bounds a bad day on a busy feed to ten
  calls at a time rather than to whatever arrived.

And the alternative is not free either — it is just differently expensive. The
keyword version this replaced cost nothing per story and cost the *user*: a
list of words per hobby that nobody could keep correct, silent misses on
everything the words didn't happen to cover, and a mental model where a
self-hosted assistant with a model configured was still doing substring
matching on headlines.

**What a model-less instance gets.** Nothing routes: a broad feed's stories
stay in that feed's river, which is exactly where they are today, and every
other part of the reader works unchanged. That is a real reduction from the
keyword version, which gave a model-less box the feature via hand-typed words.
It is the right trade anyway — the words were a worse feature dressed as
inclusion, and a local model (the answer this project argues for) does this
job for free.

## 3. The mechanism

### 3.1 One question, asked about a story

`Feeds::RouteStories` takes the stories a broad feed delivered, twenty to a
call, and asks: which one of this user's hobbies is each about, if any? The
answer is a slug from a closed set — the hobbies that already exist — plus one
sentence saying why, which is shown on the row and never read back as logic.

The prompt is `Email::Triage`'s shape, because triage solved this problem
first: a batch of numbered items, a strictly validated answer, and a system
prompt that names the material as untrusted. A story the model doesn't mention
is a story about none of them, which is the common case and the right answer.

### 3.2 Only the feeds that need it

`Feeds::Classify` answers "broad or focused?" in the same call that files the
feed. A focused feed — a woodworking blog, a subreddit, a personal site — has
its stories' tags decided by its own filing, forever, for free. Only feeds the
model called broad are ever read story by story, and `feeds.broad` is the one
column that makes the arithmetic in §2 work.

### 3.3 The exception tagging, and the invariant it amends

D-feed-reader says *an item's tags are its feed's tags, so filing happens once,
at the subscription*. This amends it in exactly one direction:

> An item's tags are its feed's tags, **plus any exception recorded on the
> item**. Nothing writes an exception without reading the story, and no
> exception ever removes what the feed's tags gave.

Exceptions live in their own table (`story_routings`: item, section, source,
reason, rejected_at), not in `section_taggings`, for three reasons:

- `section_taggings` is the user's filing of **primitives**, and an item is
  not one — it is disposable, pruned on refresh, and becomes a Task or a Note
  when it matters. Widening that table's meaning for a non-primitive is how
  "sections never own tables" starts to rot.
- A routing needs `source` (routed by the model / filed by hand), so a re-read
  can never overwrite a human's row.
- Routings churn: pruning deletes them, a re-sweep rewrites them. That churn
  does not belong in the table every section page joins against.

`FeedItem` therefore stays not-`Sectionable`, and every existing query keeps
working unchanged.

### 3.4 The river grows one OR

The hobby river becomes *items from feeds tagged with this hobby, plus items
routed into this hobby*. In `Feeds::River`, that is one OR inside `base`,
**inside the existing `user.feeds` scope** — the reader's one authorization
line ("a river is your own subscriptions") does not move, so a routing can
never show an item from a feed the viewer doesn't own, and a section grant can
never widen it. Unread counts, hub cards, the reader's rail, the lens page and
the everything-view all inherit it.

The catch-all keeps its copy: a broad feed is still unfiled, so its stories
still appear in Other Interests as well as in Birding. Nothing disappears from
where the user last saw it, and the invariant from §3 of the hub plan — every
feed has a hobby or has Other Interests — is about *feeds* and is untouched.

## 4. What the user owns: a sentence, not a rule

Routing without a handle would be an assistant filing things in a household's
name with nothing to say about it. The handle is a `HobbyBrief`: **one or two
sentences saying what this hobby means**, which ride in the prompt beside the
hobby's name, plus a switch that turns routing off for that hobby entirely.

- **It's prose, and prose can't be wrong the way a rule can.** "Local birds,
  identifying them, optics and where to go — not the band Warbler Records" is
  a sentence a person can write, argue with and delete. Nothing compares it to
  anything; it is context for a judgment.
- **The model drafts one** (`Briefs::Author`, one call per hobby) from the
  hobby's name, the feeds filed under it and the titles the user has actually
  read there — the same evidence `Hobbies::Spotter` reads, for the same
  reason. A sentence the *user* wrote is never overwritten by a drafted one.
- **Corrections are examples, not adjustments.** "Not this" tombstones the
  routing, and the story's title is shown back to the model next time as
  something the user says is *not* this hobby. There is no rule to nudge, so a
  rejection teaches the only way it can — by being read. This is strictly
  better than what it replaced: the keyword version had to *guess* which word
  was to blame and drop it, which was a rule about a rule.
- **Per user, not per section.** A lens is household-shared; a brief is shaped
  by one person's reading and one person's corrections (D9).

A new hobby is a question about the stories already here, not only the ones
still to come: creating one (or switching a brief back on) clears `routed_at`
across the recent past of the broad feeds and re-reads it — bounded to the
window a reader reads, because this is a river and not an archive.

## 5. What the user sees

- **The hobby page** gains one quiet block: *How stories reach Birding* — the
  sentence, the switch, and one line of receipt ("2 stories joined this week,
  from 1 broad feed"), plus the last few things the user turned down, named as
  the examples they now are. It sits under the river, not above it.
- **A routed row** in any river wears a small tell and, on the expanded row,
  one verb: **Not this**. That is the only new verb the reader gets, and it
  teaches (§4) rather than just hiding. The tell has two shapes because the row
  does: the phone's signal line takes a `chip-inferred` naming the hobby, and
  the laptop's row — whose signal line is `lg:hidden` — takes a funnel in the
  source column. Both carry *the model's own sentence* as their hover title, so
  "why is this Guardian story in Birding" is answerable on the row itself.
- **The counts follow the river.** A hobby's number in the reader's rail, on
  its hub card and on its page counts routed stories too, because a number that
  disagrees with what clicking it shows is worse than no number. A hobby with
  *no feeds of its own* still gets a row, a card and a river when something has
  been routed into it — that stranded case is the whole feature, so it cannot
  be the case that falls through the UI.
- **The hub card** is unchanged, and gets richer for free: a hobby whose feeds
  are quiet but whose subject is in the news now has something to show.
- **Nothing new to triage.** No tray, no "suggested stories" queue, no second
  inbox. Routed stories go into the river they belong to; the correction is one
  click on the row you're already looking at.

## 6. Correct in all cases — the list, and the answer for each

| case | what happens |
| --- | --- |
| **No model configured** | Nothing is routed. Every feed still lands somewhere and every river still fills; a broad feed's stories stay in that feed's river, which is where they are today. The hobby page says so rather than showing an empty control. |
| **Ambiguity** ("bass", "python", "mint") | The judgment a classifier is *for*. The hobby's brief is where a household says which one it means, and a wrong call is one click on the row. |
| **The model over-files** | Every routed row says why, in the model's own words, and "Not this" takes it back; rejected titles are shown back to the model for that hobby. A hobby that is being over-filled can be switched off entirely on its own page, which is a real off switch, not a rule to tune. |
| **A run-away feed** | The router reads at most `MAX_PER_RUN` stories a run and stamps each story once, so cost is bounded by what a feed publishes, not by how often anything runs. |
| **Hostile feed text** | The model picks a slug from a closed set of existing lenses and everything else it says is dropped; the prompt names the stories as untrusted. A story can never name a lens, create one, move a feed, or reach past this user's rows. The `reason` it writes is display text, capped, and never read back as logic. |
| **One story, several hobbies** | One routing per story per hobby is possible by schema; the batch prompt asks for the single best hobby, which is the honest answer for a story and keeps the prompt cheap. |
| **A routed item's feed later gains the hobby** | The routing becomes redundant; the OR dedupes it in the query, and the router never writes one for a hobby the feed already carries. |
| **The hobby is deleted** | Brief and routings cascade. The items go back to being ordinary items of their feed. |
| **The item is pruned** | Routings are `dependent: :destroy` on the item; `KEEP_PER_FEED` behaves exactly as it does today. |
| **A second household member has the same hobby** | Their own brief over their own feeds. Two households of one never touch. |
| **Sharing** | Routings live inside `River`'s existing `user.feeds` scope, so a grant can't expose an item from a feed it doesn't already expose. |
| **Non-English feeds** | A classifier reads them; there is nothing language-specific in the code at all, which was not true of the version this replaced. |
| **A feed that is 100% one hobby** | `Feeds::Classify` files it whole and marks it focused, so its stories are never read individually. |
| **The provider is down** | `routed_at` stays null, the job retries on its usual policy, and the stories are read on the next run. Nothing is lost and nothing is half-filed. |

## 7. What this needs

```
story_routings        feed_item, section, source(model|hand), reason, rejected_at
                      unique (feed_item_id, section_id)
hobby_briefs          user, section, description, enabled, authored_at
                      unique (user_id, section_id)
feeds.broad           does this feed publish about many subjects
feed_items.routed_at  has the router read this story yet
```

```
Feeds::Classify           + "broad": one more question in the call that files a feed
Feeds::RouteStories       batched per-story classification; resweep! for a new hobby
Feeds::Briefs::Author     one call per hobby → the sentence
RouteStoriesJob           after a broad feed's refresh, and after a hobby appears
AuthorBriefJob            after a hobby appears
Feeds::River              one OR, inside the existing user scope
FeedItemsController       #reject / #unreject — "Not this" and its Undo
HobbyBriefsController     the sentence and the switch
```

Everything else — the hub, the lens pages, the counts, the feed classifier,
the spotter — is unchanged.

## 8. Waves

All four are built, and then the mechanism under them was replaced once
(§10). What each turned out to be is in the build log (`bin/status`).

**W1 ✅ — the exception, and the surfaces that read it.** `story_routings`,
the river's OR, the counts on every surface that names a hobby, the tell on a
routed row, **Not this** and its Undo.

**W2 ✅ — the classifier.** `feeds.broad` from the feed's own filing call,
`Feeds::RouteStories` batched at ingest, `routed_at` so each story is read
once, the per-run cap.

**W3 ✅ — what the user owns.** The brief, the switch, the drafted sentence,
and the re-sweep when a hobby appears or is switched back on.

**W4 ✅ — the correction loop.** Rejections tombstone the row and come back as
examples in the next batch for that hobby.

## 9. Deliberately not doing (and what would change our minds)

- **Reading focused feeds' stories.** Their tags come from the feed, which is
  right by construction and free. If a household reports that a feed the model
  called focused is actually broad, the fix is a per-feed override on the feeds
  page, not reading everything.
- **More than one hobby per story.** The schema allows it; the prompt asks for
  the best one. A story that is genuinely about two hobbies is rare enough that
  paying for it in every prompt is the wrong trade — revisit if the rejections
  say otherwise.
- **Embeddings.** Still the interesting long-term mechanism for the *cheap*
  half of this (a similarity pass that decides which stories are worth a chat
  call at all), and still not reachable: `Llm::Client` speaks chat only, and an
  `/v1/embeddings` seam is a provider-capability question. Nothing in §5
  changes if it lands.
- **A suggested-stories tray.** A second inbox is a worse product than a
  slightly noisy river with a one-click correction.
- **Removing routed items from Other Interests.** The catch-all shows the feed;
  the hobby shows the story. Nothing vanishes from where you left it.
- **Routing into non-hobby sections.** The plumbing is section-generic — a
  Money routing over a CFPB feed would work unchanged — but the router is
  restricted to Hobbies' children, the same restriction `Feeds::Classify` has.

## 10. What the first build got wrong, kept for the record

The first version of this plan routed stories with **per-hobby term lists**:
the model wrote a list of words for each hobby once, the user could edit it,
and `Feeds::Match` compared those words to every incoming headline offline. It
shipped — matcher, corpus test, flood guard, correction loop and all — and
then the whole mechanism was cut in favour of asking the model about the
stories (D-no-keyword-logic).

The argument for it was cost, and the argument against it is that cost was the
only thing it was better at:

- **A word list is a rule about an open subject.** It fails silently on
  everything nobody thought to include, and the failure is invisible: a hobby
  that quietly misses half its stories looks exactly like a hobby with nothing
  in it.
- **Matching is a worse classifier than the classifier.** "Is this story about
  birding" is a judgment; `bass` is not. Every guard the keyword version needed
  — negatives, the 20%-of-your-river corpus test, the flood suspension, the
  term-rejection tally — existed to patch a mechanism that could not read.
- **The corrections were rules about rules.** A rejection had to *guess* which
  word was to blame and drop it. Now a rejection is an example, which is what a
  correction to a classifier actually is.
- **It was the wrong thing for this app to be doing.** An assistant with a
  model configured, matching substrings against headlines to decide what its
  user cares about, is a tell that the model was there for show.

What survived the rewrite, unchanged, is the part that was about the *user*
rather than the mechanism: exceptions in their own table, the invariant
amended in one direction, the river's single OR inside the authorization
scope, the counts that agree with what clicking them shows, and the rule that
a story in your hobby must be able to say why it's there.
