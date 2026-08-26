<!-- decided -->
**D-nav-signals. Rail tooltips carry live state, not a restatement of the row's name**
Every rail row hovered to a bubble that said what the row already said:
Career → "Career", badge "Section", subtitle "Life Lens section". That
content has exactly two audiences and serves neither. With the rail expanded
the label is two inches to the left, so the tooltip is a no-op; with it
collapsed (`nav-label` is `hidden` below 68px) the title is the only label
there is, and the badge and subtitle are still noise beside it. A tooltip is
a costly gesture, and it was buying a word already on screen.

**The one question a nav tooltip can answer is "is there anything in there
for me right now?"** — which is state, and state is the one thing a static
rail cannot show. So the subtitle slot becomes `detail`: what is behind that
door. `Navigation::Signals` builds one line per row, in the vocabulary the
hub cards settled on — **a date beats a count, a count beats nothing, and
nothing renders as nothing.** A quiet row collapses to its bare title rather
than drawing a filler line, because "Nothing yet" costs a row of bubble to
say less than blank does. The `badge` slot stops being a category name and
becomes a state worth doing something about: `Overdue`, `Needs action`.

**Sealed containers are not signalled.** Passwords and Diary
(D-passwords-vault, D-diary-vault) have no row in `Signals#row`: a hover must
not leak how much is inside a container the user locked. That is a rule about
the seam, not an oversight — a third sealed container gets the same silence.

**Batched, because the rail is on every page.** One `Signals` per render
(memoized in the helper), every number an aggregate, nothing computed for a
row the rail didn't draw. Sections reuse `Sections::Summary` (three queries
for all lenses); the dashboard row counts lenses over data those rows already
loaded, so it costs nothing; a vault pile groups on a boolean so its size and
its week's arrivals come back in one pass instead of two `COUNT(*)` walks.
The alternative — fetching a row's detail lazily on hover — was considered
and not built: it trades a dozen local SQLite aggregates for a request per
hover and a tooltip that arrives late, and this app runs against a file on
the user's own machine.

**A collapsed rail was unlabelled for anybody not using their eyes.** The
labels collapse with `display: none`, which removes them from the
accessibility tree too, and the tooltip lived outside it entirely — so the
icon-only rail was a column of unnamed links. Nav links now carry
`aria-label` (a subsection by its `qualified_name`, so "Budget" is announced
as "Money · Budget"), and the bubble is wired up as the trigger's
`aria-describedby` with its title `aria-hidden`, so a screen reader hears the
state once and the name once.

**The `⌘1`–`⌘4` and `⌘[` hints were fiction and are gone.** Nothing in
`app/javascript/controllers/` ever bound them. Implementing them was the
other option and was declined: `⌘`+digit is tab switching in every major
browser, and a `g`-prefix scheme is a keyboard-nav feature, not a tooltip
fix. A hint that lies is worse than no hint.
