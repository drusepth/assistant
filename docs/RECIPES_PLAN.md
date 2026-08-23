# RECIPES_PLAN.md

Build plan for the **recipe box**: saving recipes, curating them into recipe books
(a spring book, a soup book, Grandma's book), and sharing them — privately by
default, to the household in one click, and to people *outside* the household
through read-only links. Later waves add the pantry and the AI features that
sit on top of it (what can I make tonight, what do I need to buy).

Decisions here are logged as **D-recipe-primitive**, **D-share-link**, and
**D-pantry** in `DECISIONS.md`. Open questions are **Q-recipe-nutrition**,
**Q-recipe-scale-units**, and **Q-recipe-collab**.

---

## 1. What we're building and why

Feeding a household is the most relentless recurring project an ordinary family
runs: seven dinners a week, a budget, somebody's allergy, a fridge with three
things in it, and a stack of knowledge that currently lives in a shoebox, six
screenshot folders, and a phone call to your mother. The paid version of this
service is a meal-kit subscription; the free version is a recipe site that
buries a four-line method under 900 words of memoir and eleven ad slots, and
which quietly owns the collection you paste into it.

This is the mission's shape exactly: the recipes are *your* durable asset, the
model is swappable, and the thing an assistant should do with them —
"here's what you can make with what's in the house" — is worth more than the
recipes themselves. It also puts the app in the kitchen, which is the room a
household is actually in.

The baseline we're aiming at (Paprika / AnyList / a shared Google Doc, done
better because it's yours):

- **Save a recipe in one paste.** Ingredients arrive as text and become
  structure without anybody filling in a form.
- **Books** — user-curated containers: Summer, Soups, Weeknight 30-minute,
  What Dad Actually Eats. One recipe in many books.
- **Cook from it** — scale servings, read it on a phone on a counter.
- **Share it** — private by default (D9), to the household in one click, and
  to Grandma (who has no account and never will) by a link.
- **Then the assistant earns its keep** — pantry-aware suggestions, a grocery
  list that subtracts what you already have, a week planned onto the calendar.

Deliberately **not** in v1: nutrition facts (Q-recipe-nutrition), barcode
scanning, recipe scraping from arbitrary URLs (needs the Q9 web capability —
paste works today), and collaborative books (Q-recipe-collab).

---

## 2. The decisions

### D-recipe-primitive. Recipe is the eighth primitive; ingredients are rows, method is prose; books are containers.

A recipe is not a Document (a Document is a file with extracted text; a recipe
is a structured thing you *do*), not a Note (it has quantities, servings, and a
cook history), and not a Task. It is a first-class owned object with its own
browsing idiom, so: **`Recipe` joins Event/Task/Document/Person/Goal/Note/Photo
as the eighth primitive** — `belongs_to :user`, `include Visible`, `include
Sectionable`. Recipes surface through a new top-level **Recipes view** in the
sidebar's vault group (the Photos/Documents pattern), **not** an eighth
section: D3's seven sections are locked, and food is not one life-area — a
recipe multi-tags into Health (the low-sodium ones), Money (the £2-a-head
ones), People (Grandma's), and Hobbies (the sourdough lens) like everything
else.

**Ingredients are structured rows; the method is prose.** This asymmetry is the
one real modelling call here, and it follows from what each half is *for*:

- Ingredients have to be machine-readable — the pantry match, the grocery
  list, and scaling all key off "1 kg of flour", not off a sentence. So
  `recipe_ingredients` rows carry `quantity`, `unit`, `item`, a normalized
  `item_key` for matching, an optional `note`, and — always — the `raw` line
  as typed.
- The method has no relations. Nothing joins to step 4. Storing it as text
  keeps the editor a textarea, and the show page renders the numbered list by
  splitting it.

**Capture stays a paste** (D16). The ingredients field is one textarea, one
ingredient per line, parsed by a deterministic parser (`Recipes::Parse`) on
save — quantities including `1 1/2`, `½`, and `2-3`; a canonical unit table
with aliases (`tbsp`/`tablespoons`/`T`); trailing notes after a comma;
`(optional)`. No model call is needed to save a recipe, ever. Round-tripping is
lossless because `raw` is kept: the edit form re-renders exactly what was
typed, so a line the parser reads badly is still *right* on screen and can be
fixed by hand.

**Books are user-owned containers, not sections** — the same reasoning that
made albums containers (D-photos-primitive): a book is deliberate curation, one
recipe lives in many books, and books are themselves `Visible`. `Recipe` gains
the same fourth OR-branch albums gave photos: *a recipe is visible to anyone
holding a grant on a book containing it, when the grant's grantor owns the
recipe*. `AccessGrant` stays the one household sharing mechanism and
`visible_to` stays the one read path.

**Cooking is logged, not tracked.** One "Cooked it" button stamps
`last_cooked_on` and bumps `times_cooked`. That's the whole signal — it costs
one tap, and it's what later watchers ("you have made 6 dinners for a year"),
sorting ("what we actually eat"), and the suggester read. No ratings, no
timers, no streaks: the trap this feature dies in is making *tracking* the
hobby (the HOBBIES.md lesson).

### D-share-link. Read-only public links are the first sharing path that leaves the household — allowlisted, unguessable, revocable.

Everything before this was household-only by construction: `AccessGrant`
validates that grantor and grantee share a household. But a recipe's natural
audience includes your sister in another state and the friend who asked for it
at dinner, and telling that user "create them an account on your home server"
is the kind of answer that loses a household to a website. So a second,
deliberately narrower mechanism:

```
share_links: user, subject (polymorphic), token, label, expires_at,
             views_count, last_viewed_at
```

- **Allowlisted subjects.** `ShareLink::SHAREABLE_TYPES = %w[Recipe
  RecipeBook]`, enforced by a validation *and* by the controller's lookup
  table. This is a public, unauthenticated read path; it must never become a
  generic one that a later feature can accidentally point at a medical
  document. Adding a type to that list is a decision, made once, on purpose.
- **Unguessable and revocable.** A 24-character `has_secure_token` (~140 bits)
  at `/s/:token`; deleting the row kills the link immediately. Optional expiry
  (never / 7 days / 30 days), evaluated at request time.
- **Read-only and minimal.** The public page renders on its own bare layout:
  the dish, the ingredients, the method, the notes, the source, and "shared by
  <first name>". No section chips, no email addresses, no other recipes, no
  app navigation, no way in. `X-Robots-Tag: noindex, nofollow` so a forwarded
  link doesn't become a search result.
- **Visible, like every other grant (D9).** Links are listed on the item they
  share with their label, view count, and last view, and revoked from there.
  A link is a thing the user made and can see — never an ambient setting.
- **Owner-scoped creation.** Only the owner of the subject can mint one; the
  household-grant path is untouched and stays the *default* answer for people
  who do have accounts.

The mechanism is general on purpose but enabled narrowly: when photos or
documents want public links later, they add themselves to the allowlist and
inherit the plumbing rather than inventing a second one.

### D-pantry. The pantry is a container whose grant exposes its contents; matching is deterministic SQL.

(Designed now because the AI features depend on its shape; built in W4.)

A pantry is a fast-churning list where a per-item grant would be absurd, so it
reuses the container-grant pattern one more time: a single `Pantry` row per
user (created lazily, `Visible`), with `pantry_items` beneath it (`item`,
`item_key`, free-text `quantity_note`, `location` ∈ pantry/fridge/freezer,
optional `expires_on`). Sharing your pantry with the household is one grant per
member on the pantry — the "share with everyone" button already does this.

The match between what's in the house and what a recipe needs is **plain SQL
over `item_key`**, not a model call: a recipe's score is the fraction of its
non-optional ingredients present. That keeps the flagship feature working on an
instance with no model configured at all, and keeps the LLM where it belongs
(phrasing and judgement, never the decision — the D20 watcher discipline).

---

## 3. Data model

```ruby
create_table :recipes do |t|
  t.references :user, null: false, foreign_key: true
  t.string  :title, null: false
  t.text    :description
  t.text    :directions                # prose; rendered as numbered steps
  t.text    :notes                     # cook's notes — travels with a share
  t.string  :source_name               # "Grandma", "NYT Cooking"
  t.string  :source_url
  t.integer :servings
  t.integer :prep_minutes
  t.integer :cook_minutes
  t.boolean :favorite, null: false, default: false
  t.date    :last_cooked_on
  t.integer :times_cooked, null: false, default: 0
  t.timestamps
end

create_table :recipe_ingredients do |t|
  t.references :recipe, null: false, foreign_key: true
  t.integer :position, null: false
  t.decimal :quantity, precision: 10, scale: 3   # nil for "salt to taste"
  t.string  :unit                                 # canonical: g, ml, cup, tbsp…
  t.string  :item, null: false                    # "all-purpose flour"
  t.string  :item_key, null: false                # "flour" — the match key
  t.string  :note                                 # "finely chopped"
  t.string  :raw, null: false                     # the line as typed
  t.boolean :optional, null: false, default: false
end

create_table :recipe_books do |t|
  t.references :user, null: false, foreign_key: true
  t.string :title, null: false
  t.text   :description
  t.references :cover_recipe, foreign_key: { to_table: :recipes, on_delete: :nullify }
  t.timestamps
end

create_table :recipe_book_entries do |t|   # unique (book, recipe)
  t.references :recipe_book, null: false, foreign_key: true
  t.references :recipe, null: false, foreign_key: true
  t.integer :position
  t.timestamps
end

create_table :share_links do |t|           # unique token
  t.references :user, null: false, foreign_key: true
  t.references :subject, polymorphic: true, null: false
  t.string   :token, null: false
  t.string   :label
  t.datetime :expires_at
  t.integer  :views_count, null: false, default: 0
  t.datetime :last_viewed_at
  t.timestamps
end
```

- **`Recipe`**: `Visible` + `Sectionable`; `has_one_attached :image` with
  preprocessed `:card` (600px, WEBP, stripped) and `:hero` (1600px) variants —
  the Photo convention, so the original is never served and a phone JPEG isn't
  shipped to a grid tile. `ingredients_text` is a virtual attribute: assigning
  it replaces the rows through `Recipes::Parse`; reading it re-joins the `raw`
  lines.
- **`RecipeBook`**: `Visible`, not `Sectionable` (curation, not a life area).
  Cover falls back to the most recently added recipe with an image.
- **`ShareLink`**: `belongs_to :subject, polymorphic: true`, allowlisted, owner
  validated.
- **Search** is a plain LIKE over title, description, and ingredient items —
  SQLite, one query, no index ceremony until it hurts.

---

## 4. UX

### The library (`/recipes`)

Card grid — dish photo (or a warm placeholder), title, total time, servings, a
"cooked N times" whisper, section chips, and a `Ui::UserLabel` when it's shared
*to* you. Above it: a search field, the section chip row (the Photos filter
convention), and filters for favorites and "in a book". Empty state offers the
one thing that matters: paste a recipe.

### One recipe (`/recipes/:id`)

Hero image, then the two columns that a cook needs and nothing else:
ingredients left, method right (stacked on a phone). Above them: servings,
prep/cook time, source. Below: notes, the books it's in, section chips.

**Scaling is a link, not JavaScript.** `?servings=8` re-renders the ingredient
quantities multiplied by `8 / recipe.servings`, formatted back into kitchen
fractions (1½, not 1.5). It survives a page refresh, works with JS off, and on
a phone in a kitchen it is one tap on a stepper. Lines the parser couldn't
quantify are shown unchanged — never invented.

Owner-only, below: **Sharing** (the standard household card, plus the
share-link card), Cooked it, Edit, Delete.

### Capture and edit

One form. Title, an optional photo, servings and times, source, then two
textareas — ingredients (one per line, paste-friendly, hint text showing
`200 g flour`) and method — plus notes and the section picker. The parser runs
on save; the edit form shows the raw lines back.

### Books (`/recipe_books`)

Index of covers (own + shared-with-me), book page = cover header, description,
its recipes in the same card grid, and the two sharing cards. "Add to book"
lives on the recipe page as a menu of the user's books; removing a recipe from
a book never deletes the recipe (the album rule).

### Sharing, three ways, one place

The recipe and book pages carry one Sharing section with two cards:

1. **Household** — the existing `shared/_share_controls` partial: per-member
   grants and "Share with everyone in the household". Unchanged mechanism.
2. **Link** — "Anyone with the link can read this recipe." Create with an
   optional label ("for Mum") and an expiry; the list shows each live link,
   its views, and a Revoke button. Copy-to-clipboard is a Stimulus nicety over
   a link that's selectable anyway.

The wording is deliberately plain about what a link means, and the card only
exists on the two allowlisted types.

---

## 5. The AI wave (designed now, built in W5)

Every one of these degrades to something useful with **no model configured**,
because the arithmetic half is deterministic:

1. **Paste-import a recipe** (`import_recipe`, draft tool). Input: a blob of
   pasted text (a blog page, a forwarded email, a photo of an index card when
   the profile is vision-capable). One call returns the DRAFT-shaped JSON —
   title, servings, times, ingredient lines, method — which lands as an
   *unsaved* recipe form for the user to confirm (D6: the model proposes, the
   human saves). Ingredient lines still go through the deterministic parser.
   Without a model, the paste box is still there: it just goes straight into
   the ingredients textarea.
2. **What can I make?** (`whats_for_dinner`). SQL ranks the user's visible
   recipes by the fraction of non-optional ingredients whose `item_key` is in
   the pantry, with "missing 1" and "missing 2" tiers. That list *is* the
   feature. The model, when present, picks among the top handful with a reason
   ("the chilli — you have everything but coriander, and the mince is oldest")
   and can suggest a swap. Filters ride existing data: time available,
   section tags, who's home.
3. **Grocery list** (`grocery_list`) — **no LLM at all**. Pick recipes (or a
   book, or the week's meal plan) → union their ingredients → merge by
   `item_key`, summing compatible units → subtract the pantry → group by aisle
   using a small static table → land as a Note (and optionally one Task).
4. **Plan the week** (`meal_plan`, plan tool). Constraints in (nights, budget,
   what's in the pantry, dietary notes from Health), plan out: an all-day
   Event per night with `events.recipe_id` set, so **the week's dinners appear
   on the Calendar for free** and the grocery list for the plan is one click.
   That FK is the whole integration — the lens model paying out again.
5. **Watchers** (deterministic, D20): `pantry_expiry` ("the cream goes off
   Thursday — three recipes use it"), `recipe_rut` (the rotation has been the
   same six dinners for two months, here are three you saved and never made),
   `seasonal_book` (the spring book, in spring).

Cross-section dividends, unbuilt but free-by-construction: Money (grocery
spend already has a Groceries budget category; the list can carry an estimate),
Health (allergies and diet from care settings feed the suggester's filter),
People (a recipe tagged to Grandma; a share link to the family), Hobbies
(a Baking lens over the same recipes).

---

## 6. Build waves

Each wave lands green (`bin/rails test`, `bin/rubocop`) and is independently
shippable.

| Wave | Contents | Status |
|---|---|---|
| **W1 — the primitive** | `recipes` + `recipe_ingredients`, `Recipes::Parse`, model + `Visible`/`Sectionable`, CRUD, library with search/filters, show page with servings scaling, cook log, sidebar entry | ✅ built |
| **W2 — books + household sharing** | `recipe_books` + entries, the book-grant visibility clause, book CRUD + covers, add/remove from book, `AccessGrant` type registration, sharing cards | ✅ built |
| **W3 — links out of the household (D-share-link)** | `share_links`, `/s/:token` public page + bare layout, noindex, expiry, revoke, view counting | ✅ built |
| **W4 — the pantry (D-pantry)** | `Pantry` + `pantry_items`, the container clause, quick-add UI, the deterministic match query and its "what can I make" surface | planned |
| **W5 — the AI wave** | `import_recipe`, `whats_for_dinner`, `grocery_list` (no LLM), `meal_plan` + `events.recipe_id`, the three watchers | planned |

W1–W3 are the storage-and-sharing foundation the rest hangs off: they are worth
shipping alone (a recipe box you own, shareable to anyone, is the whole
Organize mode for food), and they fix the data shapes W4/W5 need.

## 7. Open questions

- **Q-recipe-nutrition.** Nutrition per serving wants either a food database
  (a large static dataset, an import job, licensing) or a model that will
  cheerfully hallucinate calories. Neither is v1. Revisit as a dataset import
  (the `datasets` service already does this shape) rather than an LLM feature.
- **Q-recipe-scale-units.** Scaling multiplies numbers; it does not convert
  units, and it does not know that you can't scale a 9-inch cake by 1.5. v1
  scales quantities and says nothing else. Does the unit table eventually need
  g↔oz conversion (useful) and a "don't scale this line" flag (honest)?
- **Q-recipe-collab.** A household cookbook that everyone adds to needs the
  contribution guard the album SQL already carries (`grantor = owner`). Same
  question as Q15, same answer for now: decide after real use.
