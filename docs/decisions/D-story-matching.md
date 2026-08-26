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
small tell, with one new verb — "Not this" — that deletes the match and
teaches the rule. A suggested-stories tray would be a second inbox, which is
the thing this app exists to not be.

Plan, waves and the full case list in `docs/STORY_ROUTING_PLAN.md`. Embeddings
are the acknowledged long-term mechanism and are not reachable yet
(`Llm::Client` speaks chat only); the surface is deliberately mechanism-shaped
so centroid similarity can replace term matching later without changing
anything the user sees.
