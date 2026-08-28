**Goal cards drop their section tags**: the goal card (`goals/_goal`) no
longer renders section chips — streamlining the design so the card carries
one outcome, its progress, and its date, and nothing else. The tags belong
to the day-sized tasks the goal spawns, which still show them.

The someone-else's-item attribution stays: `shared/_item_chips` grew an
optional `sections: false` local that drops the chips and keeps the
`from <name>` marker, rather than the card skipping the shared partial and
losing the one marker every primitive row is supposed to carry. The chip row
now renders only when there is a target date or a shared owner, so a plain
goal card ends at its progress bar instead of an empty flex row.

Affects every place the goal card renders — the Tasks board, section pages,
and tool-run results — since they all render the same partial.
