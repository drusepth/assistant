# The /about pages

How the app explains itself — to someone deciding whether to run it, and to
someone already running it who wants to know what a feature does.

See **D-about-pages** for the decision this rests on.

## 1. The problem

Everything the app can do is currently discoverable only by clicking around
inside it while signed in. That fails two people:

- **The prospective self-hoster.** They have heard there is a private life
  assistant they can run at home. They want to know what it does, what it
  costs them in hardware, and whether it phones home — before they install
  anything. Today the only answer is the repository's README and a pile of
  design documents written for the people building it.
- **The household member already running it.** They opened the Money
  section and found a spending ledger, a budget, and eleven tools. Nothing
  on the page explains what "taught rules" are, or why the letter tool
  hedges about state law. The knowledge exists — in `docs/` — in a form
  nobody outside this repository will ever read.

One set of pages serves both, because the honest answer to "what does this
do?" is the same answer either way. What differs is only the order: the
prospective user needs the *why* first, the running user needs the *what*
first, and the page structure gives each of them their entry point.

## 2. Shape

Nine or so top-level pages, ten hubs, ~25 feature pages, ~60 tool pages —
all under `/about`, all rendered by the app.

```
/about                        the front door: what this is, in three promises
/about/why                    the mission — rent vs. own
/about/privacy                nothing leaves your network (the flagship page)
/about/models                 local models, explained for people who've never run one
/about/install                one command, and what to expect after it
/about/household              multiple people, one box, private by default
/about/faq
/about/open-source

/about/sections/:slug         the ten hubs
/about/features/:slug         one page per substantial feature
/about/tools                  the tool directory, filterable
/about/tools/:slug            one page per tool (~60)
```

### The ten hubs

Eight of them are the app's sections. Two more exist because a large amount
of what is built does not live in any section, and would otherwise be
homeless:

| Hub | Covers |
| --- | --- |
| `health` | care radar, visit prep, results explainer, insurance toolkit, pets |
| `money` | budget, spending ledger, subscriptions, debt, benefits |
| `career` | job search, applications, interviews, pay, negotiation |
| `education` | the curriculum spine, tutor, reviews, records |
| `people` | circles, staying in touch, gatherings |
| `hobbies` | hobby hubs, the reader's rivers, finding people |
| `rights` | the letters people otherwise pay a lawyer for |
| `travel` | the photo world map, trips |
| `your-day` | dashboard, calendar, today, tasks & goals, notes, chat |
| `your-stuff` | documents, photos, recipes, email, passwords, diary, feeds |

`your-day` is the Organize-mode hub — the "useful with zero AI" argument,
which most visitors will not expect and which is the app's strongest
opening move against a skeptical reader.

### Hub page anatomy

Every hub is the same six blocks, so they are cheap to write and scan the
same way:

1. What this area of life costs you today (the problem, in one paragraph)
2. What the section shows you at a glance
3. The tools, as cards linking to their tool pages — curated via the
   registry's `featured:` list where the full set runs long (tools register
   on several sections, so Money's sixteen include "I lost my job"; a
   curated hub shows its six and links to the rest in the directory)
4. What it does proactively, and the dial that controls it
5. Links to each feature page under this hub
6. What is private and what is shareable here

## 3. Tool pages are the point

There are ~60 tools in `Tool::SLUGS`, and each one matches a moment
somebody is actually, urgently trying to solve: fighting an insurance
denial, answering a debt collector, reading a pay stub, getting a deposit
back. These are the highest-intent pages on the site and the most likely
entry point from a search engine.

They are **generated from the registry**, not hand-written. Every tool
class already declares `title`, `description`, `section_slugs`, `kind`, and
its `inputs` with labels and hints. That is enough for a real page: what it
is, what it asks you for, what you get back, which section it lives in,
what it routes to next. Prose lives in an optional per-tool file, so the
flagship ten can be hand-written without the other fifty going stale.

This has a second effect worth having: a tool whose registry metadata
cannot produce a decent page has a naming problem inside the app too.

## 4. The switch

`households.public_pages_enabled`, boolean, default `true`, admin-only,
edited from Settings.

- It gates **unauthenticated** access only. A signed-in household member
  always reads `/about` — turning off the public site must not delete the
  family's own documentation.
- Off means **404**, not 403. A 403 confirms the thing it hides.
- `robots.txt` is dynamic: it disallows `/about` when the switch is off. A
  static one would advertise exactly the paths the switch was flipped to
  hide.

Why default on: the pages are byte-identical on every install (D-about-
pages), so there is nothing about *this* household to broadcast, and a
self-hoster who never finds the switch still gets the docs.

## 5. Security posture

`/about` is the second unauthenticated read path after `/s/:token`
(D-share-link), and inherits its posture.

- Its own bare layout: no navigation, no session chrome, no household name,
  no email addresses. One sign-in link.
- **No user input reaches a template lookup.** Every page resolves through
  a registry of known slugs; an unknown slug is a 404. This is the rule
  that keeps a wildcard route from becoming a file-read primitive.
- Rate-limited like the app's other public door.
- No database reads of household data anywhere in the tree. The only
  records these pages touch are the tool registry (code) and the section
  taxonomy (seeded, identical everywhere).

## 6. Voice

The target reader is the 99% — not power users. Two rules:

- **No architecture words.** "Sections" and "household" are public
  vocabulary. "Lens", "primitive", "sectionable", "mirror layer" are not,
  and never appear outside `docs/`. Pinned by
  `test/integration/about_content_test.rb`, which scans the about views
  for the banned list; ERB comments are exempt, because they're for the
  next builder.
- **Honesty is the strategy.** Local models are worse at some things than
  the hosted ones people have tried. A page that says plainly which
  features are happy on a small model and which want a big one earns more
  trust than one that glosses — and trust is the entire product.

## 6a. Drift: facts come from code, or they come with a pin

A documentation tree that ships with the app rots page by page unless
every fact on it has a mechanism keeping it true. Two mechanisms, chosen
per fact:

- **Computable facts are computed.** The tool count is `@tools.size`, a
  hub's tool cards come from the registry, a tool page's inputs come from
  the class, the follow-up cap is `Tool::Base::MAX_FOLLOW_UPS`, the hub
  count is `@hubs.size`. If a template states a number the code knows, the
  template asks the code.
- **Prose facts get a tripwire.** Some facts no template can compute — a
  class name can't become "the password vault", so the privacy page names
  the sealed containers in prose. Each such fact is pinned in
  `about_content_test.rb`: the pin asserts the code-side value, and its
  failure message lists every page stating the fact. Growing
  `VaultSealed::CONTAINERS` turns the stale page into a red test naming
  what to rewrite, instead of a lie nobody notices.
- **Counts that are neither are written out of the prose.** "Three
  features reach outside the house" became "a short list", so the next
  entry is an append rather than a rewrite.

Two request-level pins back these up, in `about_controller_test.rb`: every
internal `/about` link on every page must resolve (the dead-link crawl),
and every tool must be reachable from a hub or from the directory's
contextual block — a tool registered on a section no hub claims fails the
build rather than silently vanishing from the site.

## 7. Screenshots need a demo household

Every page wants images, and real data is private by definition. So the
screenshot pipeline needs a seeded fake family — fake people, fake
documents, fake ledger — as a first-class repository asset, driven from
system tests so the images regenerate rather than rot. This is its own
wave, and it is the part most likely to be underestimated.

**The family is built** (`db/demo.rb`, `bin/rails demo:seed`): the
Okafor–Lynch household of Millbrook, Ohio — Kay, who schedules surgery at
the local hospital; Danny, laid off from an HVAC job in July; Ify, fifteen
and homeschooled since the anxiety got bad; two pets; and Kay's mother Ada,
who fell in June. Three logins, ~350 records, every section and subsection
populated. The screenshot pipeline on top of it is still to come.

One rule made it worth writing rather than generating: **the lore crosses
sections.** Danny's layoff is a Career note, a Money shortfall, a Health
insurance question and a Rights claim for unpaid overtime, and it is the
same event in all four. Ify's 2023 appendectomy is a Health record, a
medical debt, and a collections letter with a 30-day window. That is the
app's architectural argument — lenses over one pool, not silos — and a
demo whose sections held unrelated filler would quietly contradict it on
every screenshot. `test/models/demo_test.rb` pins it.

Two things the seed proved by having to work around them, both worth
knowing:

- **Sealed containers can only be written by something holding the
  password.** The demo creates credentials and diary entries by unlocking a
  keyring with the known demo password and going through `Vault::Share` —
  not by inserting rows, which it *cannot* do. That friction is the
  guarantee working.
- **Times are wall-clock times in the household's kitchen.** Parsed in the
  process default they land hours out, and a 9am church service renders as
  5am. The seed runs inside `Time.use_zone(household.zone)`, and a test
  pins the service at 09:00.

## 8. Build sequence

Each wave is its own branch.

- **Wave 0 — the spine. ✅** Migration, `About::Page` registry, controllers,
  layout, the switch, dynamic robots, Settings checkbox, `/about` index.
- **Wave 1 — the vertical slice. ✅** `/about/privacy`, one hub
  (`money`), one feature page (`budget`), the tool directory, and all
  generated tool pages. Enough to lock the pattern before ~100 pages exist
  in that shape. A hardening pass followed (§6a), plus OG tags and the
  layout's closing call to action.
- **Wave 2 — the top-level pages. ✅** why, models, install, household,
  faq, open-source.
- **Wave 3 — the remaining hubs. ✅** health, career, education, people,
  hobbies, rights, travel.
- **Wave 4 — the feature pages. ✅** 29 of them, and the sitemap.
- **Wave 5 — the screenshots.** A seeded demo household and a pipeline that
  regenerates images from system tests. Still to do, and the part most
  likely to be underestimated (§7).

Waves 0 and 1 landed together, since a spine with no page on it cannot be
reviewed for the thing that matters, which is whether the pages read well.

Two rules the later waves settled, worth keeping:

- **A page is registered in the same commit that writes it**, for anything
  with no generated content to fall back on — every top-level page and
  every feature page. `about_content_test.rb` pins the registry to the
  views so a row without a partial fails by name.
- **A hub needs prose when it generates nothing.** Most hubs degrade
  gracefully into their tool cards; Travel owns a section that no tool
  registers on, and the two cross-cutting hubs own none, so for those the
  prose *is* the page. The pin asks whether a hub generates tool cards, not
  whether it owns sections.

## 9. Merge hygiene

Per CLAUDE.md: **one file per page**. A hub is
`app/views/about/sections/_<slug>.html.erb`, a feature is
`app/views/about/features/_<slug>.html.erb`, a tool's prose is
`app/views/about/tools/_<slug>.html.erb`. Parallel branches adding pages
touch different files.

The registries (`About::Page::HUBS`, `FEATURES`, `PAGES`) are hub files
that conflict by design — one entry per line, resolved keep-both, never
redesigned.
