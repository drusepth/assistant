<!-- decided -->
**D-hobby-feeds. The Hobbies hub is the reader: feeds are classified per subscription, stories inherit, and only broad feeds are routed per story — without a model call**
The reader shipped as its own rail destination with a courtesy card on the
Hobbies page (D-feed-reader). That was backwards: the river is not a place to
go, it is what makes each hobby different every day. The Hobbies hub becomes a
grid of hobby cards each carrying its own three newest unread; `/reader` stays
as the everything-view, reached from the hub rather than the sidebar; the
unread badge moves to Hobbies. Full design in `docs/HOBBIES_HUB_PLAN.md`.

**Classification is per feed, routing is per story, and only the first uses a
model.** A subscription is added a handful of times per household, so one model
call there is free and is the only classification that can be right by
construction — a subreddit is about its subject in a way no single post can
contradict. A story is added a hundred times a day (228 unread across eight
feeds in two days on the instance this was designed against), so a model call
per story is a monthly bill on a hosted provider, an unusable queue on the local
models this project argues for, and a violation of the reader's third promise:
it works identically on a box with no API key. So `Feeds::Classify` files the
feed and marks it *focused* or *broad*; focused feeds' stories inherit their
feed's lenses at ingest; broad feeds' stories (news, aggregators — the case
per-feed filing genuinely cannot serve) are routed by keyword match against each
hobby's own vocabulary, which is itself AI-generated once per hobby and stored
on the lens where the user can read and edit it. A rule you can correct beats a
per-item verdict you cannot. An optional batched per-story model pass exists for
people who want it, off by default and capped at 25 items a call.

**`FeedItem` becomes `Sectionable`, reversing one line of D-feed-reader.** That
decision said an item's tags are its feed's tags so filing happens once, at the
subscription — true for focused feeds, and the reason inheritance is the default
here. It stops being true when one feed's stories belong to different hobbies.
Tags are materialized at ingest rather than resolved at query time: the hub asks
one question per hobby, a stray story can be re-filed by hand without inventing
negative tags, and pruning already caps how far the tagging table can grow.

Stories that match nothing stay unfiled, in an "Everything else" lane at the
foot of the hub — the honest home for world news in a Hobbies section, and the
input to the watcher that asks whether forty stories about climbing mean there
should be a Climbing hobby. Nothing is auto-created. A feed's title and entry
titles are a stranger's XML reaching a model prompt for the first time, so the
classifier selects from a closed set of existing lens slugs and can never name
or create one: the worst an injected entry achieves is mis-filing itself.
