<!-- decided -->
**D-radar-accounts. A linked Meetup or Eventbrite account contributes three things the app keeps apart: what you committed to is calendar sync, what you saved is a happening you already judged, and the groups you belong to are sources offered, never followed**

The listing sources of D-listing-feeds are strangers' calendars. A Meetup
or Eventbrite account holds something different — what the user has already
said about themselves — and the mistake to avoid is pouring it into the same
river as a stranger's city calendar. So the account is read through the
D26 registry (one `LinkedAccount::PROVIDERS` entry each, encrypted
credentials, read-only scopes gated by `allows?`, `SyncLinkedAccountJob`)
and its contents are split three ways. **Committed is calendar sync**: an
RSVP or a ticket is already the user's event, so `Meetup::CalendarSync` and
`Eventbrite::OrdersSync` ride `Events::Import` exactly as `Events::CaldavSync`
does — same dedupe, same window — and the events land on the calendar tagged
Hobbies and auto-sorted into a lens like any other. **Saved is a happening
the user already judged**: it lands with `provenance: saved`, `Radar::Match`
never reads it (the user's judgment is not a question for the model), the
river shows where it was saved, and the watcher nudges it inside the lead
time *with or without a model*, since no judgment is being borrowed.
**Groups are offered sources**: the calendars of the groups the user belongs
to sit on a "Your groups" shelf under each place, one tick each, and joining
a group never makes the app follow it — HOBBIES_HUB_PLAN §7.1's rule.
Attended and saved titles also become examples for the interest and causes
briefs, the way `Feeds::Briefs::Author` reads the stories the user opened,
and are never turned into a rule or a score. The platforms expose these
unevenly — Meetup has a personal iCal export of upcoming events and a group
iCal per group; Eventbrite's v3 API documents orders but not likes as of
this writing — so each lands where the platform exposes it and the account
card says which. The account never posts, RSVPs, saves or joins on the
user's behalf (read-only until Q19's consent design exists), never shares
across the household, and never sends the user's places or radius to the
platform. Design in `docs/EVENT_RADAR_PLAN.md` §9. — *Built 2026-09 (W6). Neither platform exposes likes, so the saved row is the Meetup export's own `STATUS:TENTATIVE` — the user's "maybe"; groups are typed on the account rather than read from an API; a saved row lands under the user's place whose radius covers it, else the first, else nowhere.*
