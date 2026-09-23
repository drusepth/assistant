**Pets hub empty state stops contradicting the pet cards**: with a pet on the
hub and nothing tagged Pets or her lens, the browse zone still said "Nothing
in Pets yet" directly under her card — the pet isn't a browse item, so the
generic empty state couldn't see her. Panels can now supply `empty_state`
(`Sections::Panel::EmptyState` — title, description, the section ids the
quick-add buttons tag); nil keeps the generic copy. Pets answers "Nothing
filed about Rex yet" and files straight to her lens with one pet, "Nothing
filed about your pets yet" with several, and the generic line with none.
