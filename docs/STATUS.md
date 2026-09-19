# STATUS.md

Where we left off — what is built, and what is next.

## Built

The build log lives in **`docs/status/`**, one file per entry, named
`YYYY-MM-DD-NN-slug.md` and read in filename order:

```sh
bin/status              # the whole log, oldest first
bin/status tail 10      # just the recent stretch
bin/status new "Title"  # start today's entry, prints the path
```

**One file per entry is the whole point.** This log is appended to on nearly
every branch, and while it was a single file every parallel branch collided on
it: `merge=union` made those collisions resolve silently in git, but GitHub
computes a PR's mergeability without the repo's `.gitattributes`, so every
branch that touched the log still showed a conflict on its PR page and had to
merge main locally to clear it. Separate files can't collide at all — two
branches write two different filenames, and neither git nor GitHub sees
anything to merge.

Writing an entry: `bin/status new "What landed"`, then fill in the body. Keep
the bolded lede and one entry per file — the file *is* the entry, so there's
no surrounding list to match. If two branches pick the same `NN` on the same
day, nothing breaks: the slugs differ, so the filenames do too. Never rewrite
an entry another branch is holding; add a new one instead.

## Next up

All want their own design conversation first:

1. Richer coordination (location/LLM garnish over the same signals)
2. The active agent's parked tail (`docs/AGENT_PLAN.md` §7, waves A1–A5
   built 2026-08): prepared *plan* tools (a Goal and its breakdown landed as
   one deferred graph — wants a plan-tool suggestion that demonstrably
   suffers from the form hop first), Q-agent-chat-openers, and Q19's
   outbound-action consent design, which is the trust ladder's next rung
   and should wait until prepared work has run in real houses for a while
3. Tier-B tool capabilities (Q9)
4. Project name (Q4)
5. Community packs (D11 revisit)

Ready to build without one:

6. Email follow-ons (`docs/EMAIL_PLAN.md` §10 parked list): sending mail's consent design (Q19), receipt/renewal signals feeding Money watchers over the People/mirror linkage, `person_email_addresses` normalization if single-address matching disappoints, wiring the E0 `households.region` into the Rights/Money tool prompts (Q12's other half)
7. OAuth per D27 when Google sync is next up (stateless link relay + "Sign in with Google" → first-class Google provider riding the existing importers)
8. People deferred slice (`docs/PEOPLE.md` §9.8, waits decided 2026-08): Q17 person↔item links → afterglow watcher + per-person history (wait for a second consumer), the stay-in-touch cadence upgrade (wait for a wrong-feeling nudge in real use), community tools for groups (wait for a real group living in a lens), "new baby"/co-parenting Situations (on demand)
9. The Money buildout (`docs/MONEY.md`, designed 2026-08): passes B1 (ledger) → B2 (budget + panels + build-my-budget) → B3 (faithfulness watchers) → B4 (the coach pair) → B5 (debt payoff plan, email-receipt suggestions) — B1/B2 are the meat, each pass lands green and independent
10. Event radar follow-ons (`docs/EVENT_RADAR_PLAN.md` §11, W1–W7 built 2026-09): the about page's screenshot once the demo household has a place, sharing a place across the household when one asks, a second provider when an open API appears, and a `page` source that can read a page's own "subscribe" link when LibCal's shape turns out to need it
