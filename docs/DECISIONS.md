# DECISIONS.md

Decision log from design sessions. Format: decision, reasoning, status.

The entries live in **`docs/decisions/`**, one file per entry, each named by
its ID (`D10.md`, `D-photos-primitive.md`, `Q17.md`):

```sh
bin/decisions                    # the whole log, grouped
bin/decisions open               # just the open questions
bin/decisions show D10           # one entry, or anything matching
bin/decisions new D-my-slug "…"  # start an entry, prints the path
```

**ID convention:** decisions D1–D37 and questions Q1–Q19 are numbered
historically and keep those numbers forever. New entries use kebab slugs —
`**D-photos-primitive.**` — because parallel branches sharing a counter
collide (D30 was claimed twice in one day, then the renumbered D31 collided
again the same day); slugs can't. See CLAUDE.md § conflict hygiene.

## Why one file per entry

Same reason as the build log (`docs/STATUS.md`), reached the same way. While
this was one document, every branch that recorded a decision inserted its
entry at the same anchor — the end of `## Decided` — so two branches landing
in the same week conflicted every time, and the conflict was always the same
trivial keep-both. Separate files can't collide: two branches write two
different filenames, and neither git nor GitHub sees anything to merge.

**The one collision worth keeping still happens.** The old argument for
leaving this file conflict-prone was that its conflicts forced a re-check of
D-number collisions. That argument retired with the numbers: slugs are
collision-proof by construction, and in the rare case two branches *do* pick
the same slug for different decisions, they now write the same path and git
raises an add/add conflict — a louder signal than a text conflict someone
could resolve keep-both without noticing the IDs matched.

**The group is a line in the file, not a folder.** Each entry opens with
`<!-- decided -->`, `<!-- resolved -->`, or `<!-- open -->`, and `bin/decisions`
groups on it. That is deliberate: an open question becoming a decision used to
be a delete from one section and an insert into another — two edits, two
anchors, two chances to conflict — and is now a one-word edit to one line of
one file. IDs never change and files never move, so the cross-references from
`ROADMAP.md`, `MONEY.md`, `EMAIL_PLAN.md` and the rest keep pointing at
something real.

Writing one: `bin/decisions new D-kebab-slug "One-line statement"`, then fill
in the reasoning and end with the status italic (`— *Built.*`, `— *Locked.*`,
`— *Designed; provisional until the build pass.*`). Never rewrite an entry
another branch is holding — that is the one conflict that still deserves eyes.
