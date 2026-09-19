# REMINDERS_PLAN.md

Build plan for **standing reminders** — "remind me every Thursday night to
take the trash out." The decision is logged as **D-standing-reminders**
(`bin/decisions`); D-reminders is the foundation it amends, and everything
D-reminders decided still holds.

---

## 1. The problem

D-reminders built user-armed scheduled delivery, and it works: a body, one
absolute `deliver_at`, a five-minute dispatcher, fan-out to whatever channels
reach the user's phone. But every reminder fires **once**. The whole app has
no way to say *every* — not on reminders, not on events (the ICS importer
flattens recurring events into one-off rows on purpose), not on tasks (a task
is done or not done). Trash night, meds, watering the plants, the weekly call
to a parent: the most ordinary reminders a household has are the one shape
the feature can't hold. Today the user's options are fifty-two one-shot
reminders or a hand-written `.ics` with an `RRULE`, and neither is an answer.

## 2. Where recurrence lives (D-standing-reminders)

Three places could carry it. Only one is clean.

**On the Reminder.** A reminder is already the object whose entire job is
"tell me at a time", and the dispatcher already ticks every five minutes. A
*standing* reminder is a reminder with a rule: `deliver_at` keeps meaning
exactly what D-reminders said — one absolute, indexed moment — it just now
means the **next** occurrence, and delivering it advances that moment instead
of tombstoning the row. Nothing about the `due` query, the index, the
household-zone composition, the channel fan-out, or the dial exemption
changes. The feature is a rule column and a branch in the dispatcher.

**Not on Event.** `Events::Import::Ics` states the stance at line 8: "the
events table has no recurrence model, so unbounded expansion is the
alternative." Calendar recurrence is a tarpit — moved instances, exceptions,
`EXDATE`, "this and following" edits — and a trash reminder is not a
calendar event. An Event stays one dated row.

**Not on Task, either.** This was the tempting one ("a task with a
cadence"), and it is the wrong floor. A Task's one invariant is a clear
done/not-done state, and the Tasks page plan (D-goal-pause, the staleness
markers) spends real effort defusing the graveyard of things that sit
undone. A task that respawns fights all of it: an uncompleted chore either
piles up a row per week or gets flagged stale, completing it means "this
week" rather than "done", and the Done column fills with fifty-two copies of
one chore. Recurring *tasks* are a separate product question with their own
known semantics (Todoist's "every" vs "every!" is the tell) — logged below
as **Q-routines**, not built here.

What the user actually gets from the reminder-level answer: a Task **can**
carry a standing reminder, exactly as it can carry a one-shot one today
(`Remindable` is unchanged). "Take the trash out" as a task with a reminder
every Thursday at 8pm is one form submission. The reminder pings; the task
sits on the board as the durable record of the chore, and checking it off is
the user's call. That is "reminders on tasks with a customizable cadence"
with no respawn engine and no new state.

## 3. The rule: one recurrence grammar, already in the app

The importer already parses and expands the RFC 5545 `RRULE` subset real
calendars produce — `FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`,
`BYMONTHDAY`, `BYMONTH` — with calendar-aware arithmetic that keeps the
wall-clock time across DST, ordinal weekdays ("2TU", "-1FR"), and the
skip-months-without-that-day rule for the 31st. It also renders a rule as
prose ("weekly on Thursday"). All of it is private to `Events::Import::Ics`.

**W1 extracts it** into `Recurrence::Rule`, a value object with no
ActiveRecord in it:

- `Recurrence::Rule.parse(text)` → a rule or `nil`; `#supported?` carries the
  importer's current allowlist unchanged.
- `#occurrences(from)` — the ordered enumerator that `candidate_times` is
  today, starting at `from`.
- `#next_after(time, current:)` — the one method the dispatcher needs: the
  first occurrence strictly after `time`, computed from the *current*
  occurrence. Every rule the picker composes is written **explicitly**
  (`BYDAY` for weekly, `BYMONTHDAY` for monthly) so that the next occurrence
  is a pure function of (rule, current occurrence, zone) and the row needs no
  separate anchor column.
- `#to_s` (canonical `RRULE` text) and `#describe` (`recurrence_note` minus
  the "Repeats: " prefix).

The importer delegates to it and its tests pin that nothing changed. Storing
`RRULE` text rather than bespoke `repeat`/`weekday` columns is not
ceremony: it is one grammar tested once, it round-trips to a calendar export
when reminders ever leave the app, and the picker composes it — the user
never sees the string. This is deterministic parsing and date arithmetic;
D-no-keyword-logic is not in play.

## 4. The Reminder

Two columns, one migration (`bin/rails g migration` for the timestamp):

- `rule` (string, nil) — the `RRULE` text. Nil is a one-shot reminder,
  which is every reminder that exists today; the migration changes nothing
  for them.
- `last_delivered_at` (datetime, nil) — when a standing reminder last went
  out, for the card ("last sent Thu"). `delivered_at` stays the one-shot
  **tombstone**, and a standing reminder never sets it, so `pending`,
  `upcoming`, and `due` are untouched and the existing
  `(delivered_at, deliver_at)` index keeps serving the dispatcher.

Model rules:

- `standing?` = `rule.present?`. A standing reminder is **absolute-only**:
  `rule` with `lead_minutes` is invalid. A relative reminder trails one item's
  one date; there is nothing for a rule to repeat over. `resync!` is
  unaffected because it already returns on non-relative rows.
- `rule` must parse and be `supported?`, else a validation error the form
  surfaces ("That repeat isn't one we understand").
- **Roll forward instead of refusing.** `moment_has_not_passed` says a
  one-shot in the past is an error. For a standing reminder the picked
  date/time is the *first* occurrence, and "every Thursday at 8pm" entered on
  a Thursday at 9pm should mean next Thursday, not an error: on create, if
  `deliver_at` has passed, advance it with `next_after(Time.current)`.
- `next_deliver_at(after: Time.current)` — `rule.next_after` in the
  household's zone (`local_deliver_at`, then back to UTC). Always strictly in
  the future.
- `message` is unchanged. The ping says "Reminder: Take the trash out"; the
  cadence is the card's business, not the notification's.

## 5. The dispatcher

One branch in `Reminders::DispatchJob#perform`, and the claim gets tighter,
not looser:

```ruby
if reminder.standing?
  next_at = reminder.next_deliver_at(after: Time.current)
  # Claim and re-arm in one conditional statement, keyed on the deliver_at
  # this job loaded: a second job for the same tick, or a user edit that
  # landed in between, finds nothing to claim.
  claimed = Reminder.where(id: reminder.id, deliver_at: reminder.deliver_at)
                    .update_all(deliver_at: next_at, last_delivered_at: Time.current)
  return if claimed.zero?
  return if reminder.stale?   # skip the missed ping; the series is already re-armed
  deliver
else
  # existing one-shot path, unchanged
end
```

Three properties worth stating:

- **Atomic re-arm.** There is no window in which a standing reminder is
  "delivered but not yet advanced"; the same statement that wins the claim
  writes the next moment. A double send on SMS still costs money, and this
  is the same defense D-reminders built, one column wider.
- **The series survives the box being off.** `next_after(Time.current)`,
  not `next_after(deliver_at)`: a reminder that missed three Thursdays
  advances to the coming one and pings *zero* times about the missed ones.
  D-reminders retires a stale one-shot unsent because a late ping reads as
  broken; a standing reminder applies the same judgment per occurrence and
  keeps the row.
- **Nothing else moves.** Still a poll, still one indexed `due` query,
  still `Notifications::Deliver` with the per-channel daily cap the user set.

A standing reminder ends when the user removes it (`destroy`, as today) or
when the item it hangs on is deleted (`dependent: :destroy`, as today). The
grammar understands `UNTIL` and `COUNT`; the picker does not offer them in
W3 (§8).

## 6. The picker (built)

One form for every way a reminder is set or changed — `reminders/_form` —
and the shape is the one people already know from Apple Reminders and
Todoist: the date and time, a **Repeat** select, and for the weekly repeats
a row of **weekday chips**. "Every Thursday night, take the trash out" is:
type it, Repeat → Every week, tap Thu, set 8:00 PM, Remind me. The date
defaults to today and never has to be a Thursday — it is where the series
*starts* (§4), so the picker doesn't make you hunt the calendar for the
right weekday, and the confirmation says which day it landed on.

| Option | Rule composed |
|---|---|
| Doesn't repeat | *(nil)* |
| Every day | `FREQ=DAILY` |
| Every weekday | `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` |
| Every week (chips: Thu) | `FREQ=WEEKLY;BYDAY=TH` |
| Every 2 weeks (chips: Mon, Fri) | `FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR` |
| Every month on the *19th* | `FREQ=MONTHLY;BYMONTHDAY=19` |
| Every year | `FREQ=YEARLY` |

`Reminder::REPEAT_OPTIONS` is the closed list of keys; the model composes
the rule from the key, the chips, and `deliver_on` in `before_validation`,
the same slot `compose_deliver_at` occupies, so the controller permits two
virtual attributes (`repeat`, `repeat_days`) and nothing else. A rule reads
back into those two for the edit form (`repeat_key_for`), so a row opens on
what was chosen.

The chips are checkboxes wearing chips (`.chip-toggle`, a `peer` pattern),
so one tap is a Thursday and three are Mon, Wed, Fri, and the keyboard still
reaches them. A small Stimulus controller (`reminder-form`) shows the chip
row only for weekly repeats, pre-checks the picked date's weekday, follows
the date while the chips still say what it set, and renames the monthly
option to "Every month on the 19th". All of it is presentation: with
JavaScript off the chips are simply always visible and the server takes the
date's weekday when none are checked.

Where it appears:

- **Today's standalone form** (`reminders/_upcoming`) — the case the feature
  exists for.
- **The item page** (`reminders/_controls`): the lead-time select as before
  (a relative reminder can't repeat, §4), and the same form under "Pick a
  time — once, or on repeat".
- **Every row**, opened in place. A reminder in a list (`reminders/_reminder`)
  is the fact — "Take the trash out · Weekly on Thursday · next Thu Sep 24 at
  8:00 PM" — and **Change** unfolds the same form prefilled, so "make it 8pm"
  or "actually, every day" is one tap and one form, never remove-and-redo.
  `update` joined `create` and `destroy` for this; the plan had deferred
  editing and the streamlining ask brought it forward.

## 7. Waves (all built 2026-09-19)

Each landed green and independent; W1 was pure refactor.

- **W1 — `Recurrence::Rule`.** Extract from `Events::Import::Ics`; the
  importer delegates; `test/services/events/import_test.rb` pins unchanged
  behavior; a new `test/models/recurrence/rule_test.rb` pins `next_after`
  across DST, the 31st, ordinal weekdays, and multi-day `BYDAY`.
- **W2 — the standing Reminder.** Migration, `rule`/`last_delivered_at`,
  the validations and roll-forward in §4, the dispatcher branch in §5.
  Tests: advances rather than tombstones; skips missed occurrences without
  pinging; the conditional claim loses to a concurrent advance; a standing
  rule with a lead time is invalid; created-in-the-past rolls forward.
- **W3 — the picker.** `REPEAT_OPTIONS`, the composing hook, the select and
  chips on both forms, the row that opens in place with `update`, the
  cadence text in both lists, the controller permit, a controller test per
  form. The reminders sentence in
  `app/views/about/tools/_outcome.html.erb` is the one about-page mention to
  reread.

## 8. Deferred, and one open question

- **An end date.** `UNTIL` in the picker ("until Dec 31") — the grammar has
  it; wait for someone to want it.
- **A completed task's reminders.** `Task#complete!` does not touch
  reminders, so a one-shot about a finished task still fires. Probably
  wrong for one-shots, and the question of what completion means for a
  *standing* reminder on that task (stop? keep going — it's a chore?) is
  the reason not to decide it inside this plan.
- **Natural-language capture.** "Remind me every Thursday night to take the
  trash out" typed into chat cannot create a reminder — chat writes nothing
  but a recap Note (D20/D29). A capture that parses a sentence into a
  reminder is a *tool* proposing a draft the user confirms, and it belongs
  with the other tool work, not here.
- **Q-routines (open).** A chore that *appears on the board* each Thursday
  — reopened and pulled into Today by its own cadence, checked off, gone
  until next week — is the recurring-task feature §2 declined to build on
  the Task primitive. If it is ever wanted, the standing reminder is the
  cadence it would ride: one durable Task row, one rule, the firing also
  moving the task into Today. Decide it when a household asks for it; the
  reminder-level answer here does not close it off.
