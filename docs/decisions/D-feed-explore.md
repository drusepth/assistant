<!-- decided -->
**D-feed-explore. The starter shelf is a place you can go, not an empty state you pass through**
The stocked shelf (D-hobby-feeds §7.1) was reachable from exactly three
surfaces and every one of them was gated on having nothing to read: the
reader's empty state, the feed list's empty state, and the Hobbies panel when
a household had no feeds. Following a single feed hid the whole list forever.
That was defensible when the shelf was fourteen rows of courtesy — a nudge for
somebody who had never used a reader, cleared away once they had. It stopped
being defensible when the shelf became ~150 publisher-run sources across ~48
topics: a library nobody can open after their first subscription is not a
library. `/feeds/explore` is the same list as a destination, linked from the
reader, the feed list and the shelf itself.

**Same promise, unchanged.** READER.md's first promise is that every source is
one the user chose, and Explore is still a shelf rather than a recommendation
engine: the list is the static file in the repo, identical for every user and
every install, ordered by the file and nothing else. Nothing is personalized,
nothing is scored, nothing is fetched to build the page, and nothing is
followed until a button is pressed. The thing that changes is *when* somebody
can reach it, which was never the part the promise was about.

**One click per row, because the tick-and-submit form was an empty-state
shape.** A checkbox list is right when the answer is "give me a starter set"
and somebody is setting up. It is wrong when the answer is "I got a dog last
week" and one row is what's wanted. So Explore's verb is per row, with a
"Follow all N" on each topic for the case the form used to serve, and both go
through the same `Feeds::Starters.import` — one code path, no new fetch
posture, no new parse path. Following creates the topic's hobby lens for the
same reason ticking a group did: a row picked out of *Birding* is the user
saying they're interested in birding.

**Followed rows stay on the shelf, marked.** Dropping them would be less code
(`Feeds::Starters.unfollowed_for` already existed and went unused), but a topic
that quietly loses rows reads as a list that changed its mind, and "you already
have this one" is the more useful answer to somebody scanning for what to add.

**The search is a real GET form with an instant filter over it**, the same
shape the Address Book uses (D-address-book-directory): the server filters so a
query deep-links and works with JS off, and `shelf_controller.js` narrows on
the keystroke so 154 rows feel like a shelf rather than a scroll. Both match
against `Entry#haystack` — one definition, so the two can't disagree about what
a query finds.
