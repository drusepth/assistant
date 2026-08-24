<!-- open -->
**Q-feed-sharing. Should a feed subscription (and its read state) be shareable inside the household?**
Today the river is your own subscriptions: `Feed` includes `Visible` and
`Sectionable` like every other primitive, so a section grant can expose
*what* somebody follows, but `Feeds::River` reads only the viewer's own
feeds. That is deliberate — read/saved/vote state is personal, and a shared
row would mean sharing whether you had read something, which is a
surveillance surface nobody asked for. Two members who follow the same site
each get their own row and their own fetches.

What would change the answer: a household that follows twenty of the same
feeds (duplicate fetching stops being polite), or a real ask for "look at
this" — which might be better served by a share of the *item* (as a Note or
a task) than by a shared subscription. If it is ever built, per-user read
state moves to its own table rather than staying on `feed_items`. —
*Not started.*
