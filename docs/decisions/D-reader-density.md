<!-- decided -->
**D-reader-density. The reader row is one fixed-height line at every width, opened in place rather than in a new tab**
The river shipped designed for a laptop and let go on a phone. The desktop row
was 34px and carried source, headline, the opening words and the age; the phone
row was ~96px and carried *less*. On a 390×844 device that came to six
headlines on a screen the design doc says should hold twenty, under about 200px
of chrome. Three causes, and all three are gone:

- **A chip on every row is texture, not information.** The row rendered every
  section on the feed, and Other Interests is on every feed by construction
  (D-hobby-feeds) — so a label appeared on 100% of items, carried zero bits,
  and was the highest-contrast object in the row while wrapping to two lines.
  A chip now shows only when it discriminates: never the catch-all, never the
  lens you have already filtered to, at most one.
- **The row wrapped twice.** Below `sm` the line was `flex-wrap` with a
  full-width verb row, which took a line of its own and then wrapped again
  under source + age + chip + three verbs. It never wraps now.
- **The verbs were painted 1,212 times and none of them were tappable.** The
  hover-hiding was `sm:opacity-0`, so it never applied on a phone: three text
  buttons on all 404 rows, at `text-xs` with no padding — roughly 12×30px
  against a 44×44 target. Loud enough to be noise, small enough to miss.

**Opening happens in the row.** The only way into an article was a new tab,
which meant a four-hundred item river could be triaged but never read — you
left the app once per item. A plain click now expands the row in place with the
blurb and the verbs at thumb size; `Enter` does the same from the keyboard.
That single change is what lets the collapsed row drop its preview, its verbs
and its chip, which is where the height came back from. The headline stays a
real `<a href>`, so a modified or middle click still stashes a background tab
natively and *that* row marks itself read and leaves the unread list, exactly
as it always did. Only the plain left click is intercepted.

**Identity is a face, not a truncated sentence.** `display_title` falls back to
the publisher's own feed title, so rows identified their source with a fragment
of a sentence ("World news | The G…") eating 45% of the meta line. A 20px
monogram tile, coloured from a hash of the host, does that job in a fifth of
the space. Nothing is fetched, and that is the decision rather than a shortcut:
a favicon service would be handed the list of every site the household reads,
and fetching each publisher's icon at render time would tell that publisher
when their reader opened the app — the same leak `OUTBOUND`'s `noreferrer` and
the stripped entry HTML exist to prevent. If real favicons are ever wanted, the
honest way is one fetch per feed during the poll we already make, stored, never
at render time.

**Read-on-scroll, with a ledger.** A 404-item backlog had exactly two outcomes:
404 deliberate clicks, or Mark all read — and anybody sane picked the second
and threw the pile away unseen. Items scrolled fully past the top and left
there for a beat now mark themselves read, batched into one request, with a
rail that fills as the pile clears and one Undo that restores the whole batch.
The batch narrows ids to the caller's own feeds before writing, so a forged id
updates nothing and the rest of the batch still goes through.

**And the rest of the width gets a job.** The feed filter was a wrapping
paragraph of inline link text across the top of the page — a wall at ten feeds,
unusable at forty. It is a tree now: a rail from `lg` up, and a bottom sheet on
a phone, where the thumb is. Saved gets a different shape from unread, because
they are different questions: unread is chronological triage, saved is a small
collection you come back to, so it is a card shelf ordered by when *you* kept
it. Deliberately without images — rendering a publisher's `<media:content>`
would hand them the reader's IP and a per-article read receipt from inside a
signed-in session, so the shelf is typographic and the faces carry the
identity. If images are ever wanted, they get proxied through the app.

Measured on the seeded instance at 390×844: **6 headlines on a screen became
12**, at 56px average per row rather than ~96px. On a 1440px screen the row is
37px and **21 fit**, which is the density the reader was always documented at.
Full design in `docs/READER.md`.
