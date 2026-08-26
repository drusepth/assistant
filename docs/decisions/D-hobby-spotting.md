<!-- decided -->
**D-hobby-spotting. Suggested hobbies come from what you read — clusters the model finds in Other Interests, with read stories as the signal — and naming one moves its feeds in**
The "Add another hobby" chips were a static list of fourteen broad names
(Reading, Cooking, Baking, …) minus the ones the household already had, first
four shown. Deterministic, identical on every instance forever, and blind to
the one thing the box actually knows about this user: what they follow and what
they open. Meanwhile the catch-all lens was filling with exactly that evidence
— D-hobby-feeds' Other Interests is where a feed lands when it matches no
hobby, so a catch-all that keeps filling with the same subject is a hobby
nobody has named.

**The chips are now spotted first, starters after.** `Hobbies::Spotter` makes
one model call over the unfiled feeds and returns candidate names with the
feeds that support each. They persist as `SpottedHobby` rows and lead the chip
row; the static starters fill whatever room is left, so an instance that knows
nothing about its user still offers somewhere to begin. A spotted chip wears
the feed mark and carries its reason as a hover title, with one line of caption
under the row — on a phone there is no hover, and an unexplained "Birding" is a
strange thing for the app to have opinions about.

**Read stories are the signal, and that is not per-story classification.**
D-hobby-feeds cut routing every story through a model, and that line holds:
nothing here files a story, and no per-item taggings exist. What changed is the
*evidence* the spotting call reads. A subscription says the user was curious
once; an opened story says it stuck. So each feed is described to the model by
the titles it has actually had read in the last 90 days and how many, and a
feed nothing has been opened from is described as the weak evidence it is. That
is a bounded sample of the handful of stories the user chose to open, not the
firehose — the arithmetic §2 objected to never appears.

**The model names a hobby; it never says which stories are about it.** A
candidate's `feed_ids` are feeds that are *mostly about* the subject, not a
general-interest feed that happened to carry one story on it — the invariant
stays "a feed's tags are its items' tags", so a broad feed with five birding
stories in it must not be moved under Birding whole. Two feeds still have to
support a name (`MIN_SUPPORT`), because one strongly-read feed is a feed, not
yet a hobby, and the classifier will file it the moment the hobby exists.

**Naming the hobby is what claims the feeds.** The spotter files nothing —
D20's propose-don't-dispose is untouched, and a `SpottedHobby` is a candidate,
not an action. But when the user clicks the chip (or types the same name, or
accepts the nudge and runs Start-a-hobby), `Hobbies::Spotter.claim!` moves the
feeds that candidate stood on under the new lens in that request, with no model
call: the attribution was already made when it was spotted, and paying a second
call to re-derive an answer we are holding is the kind of thing a self-hosted
box should not do. `Hobbies::MapFeeds` still runs after, because it asks about
*every* feed and a candidate only knows the unfiled ones (D-hobby-feeds §4).
Both writes go through `OtherInterests.claim!`: add-only, plus the one
mechanical drop of the catch-all.

**One call, two surfaces.** `Watcher::HobbyFromFeeds` used to own the spotting
prompt; it now reads the same candidates and keeps only the loudness policy —
one pending nudge, monthly fingerprint. So the weekly scan's single model call
feeds both the quiet surface (chips) and the loud one (the nudge), and
dismissing the nudge quiets that name's chip for the rest of the month:
one refusal, both surfaces. With no model configured, or fewer than three
unfiled feeds, nothing runs and the chips are the starter list — the same
promise-3 test the rest of the reader keeps.
