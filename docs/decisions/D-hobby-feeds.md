<!-- decided -->
**D-hobby-feeds. The Hobbies hub is the reader: the model files each feed under the hobbies it belongs to, anything it can't place goes to Other Interests, and stories are never classified individually**
The reader shipped as its own rail destination with a courtesy card on the
Hobbies page (D-feed-reader). That was backwards: the river is not a place to
go, it is what makes each hobby different every day. The Hobbies hub becomes a
grid of hobby cards each carrying its own three newest unread; `/reader` stays
as the everything-view, reached from the hub rather than the sidebar; the
unread badge moves to Hobbies. Full design in `docs/HOBBIES_HUB_PLAN.md`.

**Classification is per feed, and per story is not on the roadmap.** A
subscription is added a handful of times per household, so one model call there
is free — and it is the only classification that can be right by construction,
since a subreddit is about its subject in a way no single post can contradict.
A story is added a hundred times a day (228 unread across eight feeds in two
days on the instance this was designed against), so a call per story is a
monthly bill on a hosted provider, an unusable queue on the local models this
project argues for, and a violation of the reader's third promise: it works
identically on a box with no API key. The cheap approximation — routing stories
by keyword match against a per-hobby vocabulary — was designed and then cut
before anything was built: keywords cannot cover the open space of hobbies and
feeds that any number of users will bring, and a matcher fails silently for
everything nobody thought to enumerate. A vocabulary list is a promise to keep
enumerating the world. So a broad feed lands in one place, whole: the
Guardian's world news is Other Interests, not fifteen hobbies.

**Other Interests is a real lens, not an empty state.** Every feed has a hobby
or has this one, which means no query carries an "or untagged" branch and no
surface carries a special lane. It is an ordinary child section of Hobbies
(D25), created on demand by slug so a user's own "Other interests" hobby can't
take it, never offered as a hobby in capture or suggestions, sorted last, and
never a dead end: creating a hobby re-asks the model about the feeds sitting in
Other Interests in one batched call, so following a guitar blog before you have
a Guitar hobby fixes itself when you add one.

**`FeedItem` stays as it is.** An earlier draft of this plan made it
`Sectionable` to hold per-story tags; with per-story routing gone, so is the
reversal. D-feed-reader's line holds unchanged — an item's tags are its feed's
tags, filing happens once, at the subscription — and the whole feature costs
one nullable `feeds.classified_at` column.

A feed's title and entry titles are a stranger's XML reaching a model prompt
for the first time, so the classifier selects from a closed set of existing
lens slugs and can never name or create one (Other Interests is created by our
code, not by a model answer): the worst an injected entry achieves is
mis-filing itself, which the user fixes in one click. With no model configured
nothing runs, feeds land in Other Interests, and the manual lens picker on
`/feeds` is the whole story.
