**Household reset stopped 500ing on foreign keys nobody cascaded**: /admin →
Reset raised `ActiveRecord::InvalidForeignKey` instead of resetting on any
household that had used the vault or the Education section. Three columns
pointed at rows the cascade destroys without anything saying what should
happen to them: `vault_events.actor_id` and `.subject_user_id` (only
`user_id` cascaded, so sharing a password with your spouse made both accounts
undeletable — the same 500 hit Settings → remove member), `topics.goal_id`,
and `study_logs.topic_id`. Answered on the models rather than in the reset
service, so every delete path gets the fix: vault events go with the member
named in them, a topic outlives the goal it served, an hours log outlives the
topic it was recorded against (D-learning-record), and `app_errors` now
nullifies rather than being special-cased by the reset alone. The same audit
turned up `hobby_briefs.section_id` and `story_routings.section_id`, which
made Hobbies → remove a hobby a 500 in its own right; both now end with the
lens.

`test/models/user_destroy_test.rb` is the part meant to stop this recurring —
**found, not listed**, the same argument as the reset's blob purge
(D-purge-by-diff): it reads every foreign key into `users` and `households`
out of the schema and asserts each one is answered by an association with a
`dependent:` option (or by an `ON DELETE` on the column). A table added next
month is covered the day its migration lands. It was a hand-maintained
concern twice before and had gone stale twice.
