<!-- decided -->
**D-story-matching. The stories inside a broad feed reach a hobby through a watchlist the model writes once and the user can edit — calls scale with hobbies, never with stories**
D-hobby-feeds files feeds and never stories, which is right for the eight
feeds that are each about one thing and exactly wrong for the two that aren't:
a general news feed's birding stories are unreachable from Birding, and filing
that feed under Birding would flood it with the other 95%. The answer is
neither of the two that were already refused. Per-story model calls are still
the wrong bill (~3,000 items a month) and still break the reader's third
promise. A keyword vocabulary *we* ship is still a promise to keep enumerating
the world. What is new is the third thing: **the model writes the vocabulary,
once per hobby, from this user's own reading** — so the cost scales with
hobbies (a handful per household, ever) instead of stories, and a rule that is
wrong is visible on the hobby's own page and fixed by deleting a word.

**The rule is one sentence and the user owns it.** A watchlist is per user per
hobby (per user because it is learned from private reading and private
corrections, and a shared one would leak one member's rejections into
another's river): terms that mean this hobby, negatives that don't. A match is
a term in the title, or two distinct terms anywhere, and no negative. Terms
are validated strings — never patterns, never SQL. The whole thing is shown on
the hobby page as "What counts as Birding", editable by hand, which is also
what makes the no-model instance a first-class case rather than a degraded
one: door one is the manual door, and it is Google Reader's smart feed.

**Matching is free and offline.** It runs at ingest over the items just
written, skipping hobbies the item's feed already carries, in plain Ruby — no
model, no FTS table, no network. A rule that changes backfills over a bounded
window. Authoring is one call per hobby, plus at most a monthly re-author once
corrections accumulate; every candidate term is tested against the user's last
500 items first, and anything matching more than 20% of them is dropped before
the rule is saved. A rule is evaluated on the only corpus that matters.

**The invariant is amended in exactly one direction.** D-feed-reader's "an
item's tags are its feed's tags" becomes "…plus any exception recorded on the
item", where nothing writes exceptions in bulk and no exception removes what
the feed's tags gave. Exceptions live in their own `feed_item_matches` table
rather than in `section_taggings`: an item is not a primitive, a match needs a
`source` so a rule edit can never overwrite a hand-filed tag, and match churn
does not belong in the table every section page joins against. `FeedItem`
stays not-`Sectionable`. The hobby river gains one OR *inside* the existing
`user.feeds` scope, so the reader's single authorization line does not move
and no grant can widen what a match shows. The catch-all keeps its copy of a
matched story, because the feed is still unfiled and nothing should vanish
from where the user last saw it.

**No new queue.** Matched stories land in the river they belong to, wearing a
small tell, with one new verb — "Not this" — that tombstones the match and
teaches the rule. A suggested-stories tray would be a second inbox, which is
the thing this app exists to not be. Every count that names a hobby — the
reader's rail, the hub card, the page — counts matched stories too, and a
hobby with no feeds of its own still gets a row, a card and a river: that
stranded case is the entire feature, so it must not be the one that falls
through the UI.

**A correction removes a term; it never writes a negative.** The first draft
said a rejection would add the fired term to the negatives. That is wrong in a
way that would quietly destroy good rules: the word that fires is usually the
right word inside the wrong story — "warbler" in *Warbler Records signs a
band* — and negating it takes every real warbler story with it. So a rejection
tombstones the row and counts against the term, and a term rejected three
times and rejected more often than read comes *off* the list. Removing an
over-broad term narrows the rule; negating a good one guts it. Negatives stay
something the user types on purpose.

**The runtime guard is narrow, and it loses to the user.** A rule that starts
matching more than 40% of a week of one feed is paused *for that feed* — never
for the rule, since one loud feed says nothing about the twelve the same words
file correctly — and the notice names the words. Suspension drains the unread
matches from that feed (they are the flood, nobody looked at them, and Resume
re-derives them) and keeps the read ones, because the app does not take back
spent attention. If the user resumes, the guard does not fire on that feed
again: a warning already overruled is nagging, not safety. Changing the words
re-opens the question.

Plan, waves and the full case list in `docs/STORY_ROUTING_PLAN.md`. Embeddings
are the acknowledged long-term mechanism and are not reachable yet
(`Llm::Client` speaks chat only); the surface is deliberately mechanism-shaped
so centroid similarity can replace term matching later without changing
anything the user sees.
