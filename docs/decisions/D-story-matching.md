<!-- decided -->
**D-story-matching. The stories inside a broad feed reach a hobby because the model reads them — batched, once each, and only from the feeds it called broad**
D-hobby-feeds files feeds and never stories, which is right for the eight
feeds that are each about one thing and exactly wrong for the two that aren't:
a general news feed's birding stories are unreachable from Birding, and filing
that feed under Birding would flood the hobby with the other 95%. The answer
is the same one the rest of the app gives to every "which of these belongs
where" question: **ask the model.**

**The arithmetic that cut this before was right about the wrong thing.**
D-hobby-feeds §2 refused a model call per story at ~3,000 stories a month. It
was measuring *every* story, and almost none of them need reading:
`Feeds::Classify` now answers a second question in the call that already files
a feed — **is this feed about one subject, or many?** A focused feed's stories
inherit its hobbies forever, for free; only broad feeds' stories are read, in
batches of twenty, once each (`feed_items.routed_at`), capped per run. A
household with no broad feeds spends nothing.

**The first build of this used keyword matching, and it was replaced.** Term
lists per hobby, written by the model and editable by the user, compared
offline against every headline. It shipped and was cut: a word list is a rule
about an open subject, it fails silently on everything nobody enumerated, and
every guard it needed (negatives, a corpus test, a flood suspension, a
per-term rejection tally) existed to patch a mechanism that could not read.
The general rule is now D-no-keyword-logic; `docs/STORY_ROUTING_PLAN.md` §10
keeps the record.

**What the user owns is a sentence, not a rule.** A `HobbyBrief` is one or two
lines saying what the hobby means ("Local birds, identifying them, optics and
where to go — not the band Warbler Records"), which ride in the prompt beside
the hobby's name, plus a switch that turns routing off for that hobby. Prose
can't be wrong the way a rule can: nothing compares it to anything. The model
drafts one from the hobby's feeds and the titles the user actually read there,
and a sentence the user wrote is never overwritten. Briefs are per user, not
per section, because they are shaped by private reading and private
corrections (D9).

**Corrections are examples, not adjustments.** "Not this" tombstones the
routing — so a re-read can't undo the user's judgment — and the story's title
comes back in the next batch's prompt as something the user says is *not* this
hobby. There is no rule to nudge, which is the point: that is what a
correction to a classifier is.

**The invariant is amended in exactly one direction.** D-feed-reader's "an
item's tags are its feed's tags" becomes "…plus any exception recorded on the
item", where nothing writes an exception without reading the story and no
exception removes what the feed's tags gave. Exceptions live in their own
`story_routings` table rather than in `section_taggings`: an item is not a
primitive, a routing needs a `source` so a re-read can never overwrite a
hand-filed row, and routing churn does not belong in the table every section
page joins against. `FeedItem` stays not-`Sectionable`. The hobby river gains
one OR *inside* the existing `user.feeds` scope, so the reader's single
authorization line does not move and no grant can widen what a routing shows.
The catch-all keeps its copy of a routed story, because the feed is still
unfiled and nothing should vanish from where the user last saw it.

**No new queue.** Routed stories land in the river they belong to wearing a
small tell that carries the model's own sentence about them, with one new verb
— "Not this" — and its Undo. Every count that names a hobby (the reader's
rail, the hub card, the page) counts routed stories too, and a hobby with no
feeds of its own still gets a row, a card and a river: that stranded case is
the entire feature, so it must not be the one that falls through the UI.

**With no model configured, nothing routes** — a broad feed's stories stay in
that feed's river, which is where they are today, and the page says so rather
than showing a control that does nothing. That is a real reduction from the
keyword version, which gave a model-less box the feature via hand-typed words,
and it is the right trade: a plausible-looking wrong answer is worse for a
self-hosted assistant than an honest absence, and a local model does this job
for free.
