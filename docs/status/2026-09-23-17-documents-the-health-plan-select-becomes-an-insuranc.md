**Documents: the Health plan select becomes an Insurance statement**: every
document page asked "Health plan: Auto / Yes / No" with a Save button — a
cat's vet discharge sheet included — and a user reasonably read it as a care
plan. It meant *health insurance*, and underneath it one column held two
people's answers: the job wrote the reader's verdict into the owner's pin,
so a reader's "no" displayed as the owner's "keep it off" and a re-read
could never revise it. The verdict now lives in
`extracted_facts["health_plan"]` (a migration moves the ones already
written; every document counts exactly as before), `documents.health_plan`
is the owner's word only, and `Health::Coverage.verdict` returns the answer
and whose it is. The page shows an **Insurance** row only when the document
counts or its owner said it doesn't — where it's listed (Health coverage
card, a pet's Papers), who decided, and one inline correction ("This isn't
insurance" / "Undo"). A missed plan is marked under Edit → Advanced, which
the coverage card now points to. Open follow-up: a pet's policy also lands
on the Health page's human coverage card and its "Compare plans" pairing.
