# FOOD_PLAN.md

Build plan for the **Food section**: the tenth top-level section, a hub over
the recipe box, the household's shared shopping lists, what's in the fridge,
and the week's meals — and, on top of those, the assistant work that makes a
kitchen app worth running: "what can I make with what we have", "what should I
buy so the food we already have gets used", "the cream goes off Thursday".
The shape we're aiming at is everything Samsung Food (née Whisk) does for a
household, owned instead of rented.

Decisions here are logged as **D-food-section**, **D-kitchen**,
**D-food-catalog**, and **D-food-suggestions**. They amend two earlier ones:
D-recipe-primitive ("not an eighth section") and D-pantry (one pantry per
user; aisles from a static table; matching over `item_key`). Its own
questions — **Q-pantry-quantities**, **Q-food-shelf-life**, **Q-grocery-prices**,
and **Q-kitchen-offline** — were resolved on 2026-09-23 (§8); **Q-recipe-nutrition**, **Q-recipe-scale-units** and
**Q-recipe-collab** carry over from `RECIPES_PLAN.md` unchanged.

This supersedes `RECIPES_PLAN.md` §5 and waves W5–W6. Everything W1–W4 built
(recipes, books, share links, import) stays exactly as it is.

---

## 1. What we're building and why

`RECIPES_PLAN.md` §1 made the case: feeding a household is the most relentless
recurring project an ordinary family runs, and the paid help for it is a
meal-kit subscription. The recipe box was the Organize-mode half of that — a
collection you own. The other half is the *loop* a household actually runs
every week, and it has four stations:

```
   plan ──► list ──► shop ──► put away
    ▲                            │
    └──── cook ◄── fridge ◄──────┘
```

- **Plan** — what are we eating this week (and who's cooking, and is Tuesday
  leftovers).
- **List** — what do we need, merged across the plan, with what's already in
  the fridge subtracted, grouped the way the store is laid out, and editable
  by everyone in the house from their own phone, live, while one of them is
  standing in aisle 7.
- **Shop / put away** — checking something off in the store is the same act
  as putting it in the fridge.
- **Cook** — "Cooked it" (already built) offers to take what it used out of
  the fridge.

Samsung Food's feature list maps onto that loop cleanly: recipe saving (built),
meal planner, shared shopping lists with aisle grouping, a food list / pantry
with expiry, "cook with what you have", and personalised suggestions. What it
also does — and what this plan deliberately declines — is nutrition scores
computed by a model, a recipe social network, and smart-appliance hooks. The
first is Q-recipe-nutrition (a dataset, not a guess); the second is a
landlord's feature; the third can wait for someone who owns the oven.

The mission angle is sharper here than almost anywhere else in the app. Food
is the largest flexible line in a working household's budget, and food waste
is where it leaks: the thing a well-resourced household gets from a personal
chef or a very organised parent — *nothing in the fridge goes off, the list
is always right, dinner is decided* — is exactly the thing an assistant that
knows your fridge can do. That's the 99% case.

---

## 2. The decisions

### D-food-section. Food is the tenth top-level section; the recipe box stays in the Vault.

D-recipe-primitive refused an eighth section for recipes: "D3's seven sections
are locked, and food is not one life-area — a recipe multi-tags into Health,
Money, People and Hobbies." Since then Travel (D-travel-facet) and Pets
(D-pets-section) both became sections on the argument that a hub is a lens
over the shared pool rather than a silo, and the same argument now applies to
food. What changed isn't the recipe — it's that food grew three things that
aren't recipes (the lists, the fridge, the plan) and need a *place*, and a
section is the app's word for a place: one seeded row buys the sidebar entry,
the Settings toggle, the agent dial, the tool registry, the browse zone, and
the section grant, for free.

What D-recipe-primitive was protecting still holds:

- **Recipes keep multi-tagging.** The low-sodium soup is still Health; Grandma's
  is still People; the sourdough is still Hobbies · Baking. `CategorizeRecipeJob`
  gains Food as an option like any other section, but the hub does **not**
  depend on that tag — `Sections::Panels::Food` reads `Recipe.visible_to(viewer)`
  directly, the way the Pets panel reads `Pet`, so an untagged recipe is still
  on the Food page. The Food *tag* is for the things that aren't food objects
  but are about food: the grocery-delivery receipt (Document), the dinner
  party (Event), "learn to meal prep" (Goal), the allergist's letter (Health +
  Food).
- **The library stays in the Vault.** `/recipes` keeps its sidebar entry,
  exactly as `/photos` did when Travel arrived: the Vault is where you browse
  the collection, the section is where the life-area happens. The Food hub
  shows a strip of recipes (tonight's, recently cooked, favourites) and links
  to the library; it never re-implements it.
- **No subsections at launch.** Subsections are tag lenses, and nothing here
  wants a narrower tag than Food. The hub's zones do the organising.

Mechanics copy D-pets-section: a seed row (`[ "food", "Food" ]`, position 10)
plus a `bin/rails g migration AddFoodSection` for running boxes, with the same
slug-collision handling (a user-made lens called "Food" gets `food-2`).

### D-kitchen. The kitchen is one shared container; its lists, fridge, and meal plan are its rows, and a grant on it lets the grantee cook.

D-pantry made the pantry a container "because per-item grants would be absurd"
and gave every user one. The container half was right; *one per user* was
wrong, and it becomes obvious the moment there's a shopping list. A household
has one fridge. Two spouses who each keep a private pantry and a private list
would have to grant each other both, and the list — the thing they most need
to share — would still be read-only to one of them, because every grant in
the app today is a read grant.

So the unit is the **Kitchen**:

```
kitchens            user (owner), name ("Home", "The cabin", "My shelf")
  pantry_items      what's in it, and where (fridge / freezer / pantry)
  shopping_lists    zero or more named lists ("Weekly", "Costco", "Saturday party")
    shopping_list_items
  meals             the plan: a date, a slot, a recipe or a line of text
```

- **One grant shares the whole kitchen.** `Kitchen` is `Visible` and joins
  `AccessGrant::ITEM_TYPES`; its rows aren't primitives, carry no `user_id`
  of their own, and are visible exactly when their kitchen is. The fridge,
  the lists and the plan are the same collaboration, so they're one share.
  A roommate house that wants separate shelves makes separate kitchens.
- **A kitchen grant is the first grant that writes.** Every existing grant is
  "you can see this". A kitchen grant is "you can cook here": add to and check
  off the lists, update the fridge, fill in the plan. Renaming, deleting and
  re-sharing the kitchen stay with its owner. This is written on the share
  card in those words ("Anyone you share this kitchen with can add to its
  lists, check things off, and change what's in the fridge") because D9 is
  about the user seeing what a share means, and this share means more than
  the others. The permission lives in the kitchen's controllers
  (`Kitchen#cookable_by?(user) = visible_to?(user)`), not as a new column on
  `AccessGrant`: there is no read-only kitchen share worth offering, and a
  permission level on every grant is a much bigger decision than this
  feature needs.
- **It sidesteps Q-recipe-collab and Q15 rather than answering them.** Those
  questions are hard because a contributed *primitive* has its own owner, so
  someone else's photo in your album raises "whose is it, and who can take it
  back". A list item has no owner — it's a row of the list, like a line in a
  document — so nothing about co-editing a list needs the answer. Rows carry
  `added_by_id` / `checked_by_id` for display ("Sam added this"), never for
  permission.
- **Created with a question, not a default.** The first visit to the Food
  page creates the user's kitchen ("Home") and, when the household has other
  members, shows one card: "Share this kitchen with Alex and Sam?" with the
  existing bulk-grant button. Nothing is shared until the click (D9) — but the
  card is where it is because a kitchen almost always *should* be shared, and
  it stays on the hub until answered either way.
- **Meals are rows of the kitchen, not Events.** `RECIPES_PLAN.md` §5 planned
  an all-day Event per dinner with `events.recipe_id`. That makes every dinner
  a separately-owned, separately-granted private item — the per-item-grant
  absurdity D-pantry rejected, moved to the calendar — and it means your
  spouse can't swap Tuesday and Wednesday. A `meals` row (`date`, `slot` ∈
  breakfast/lunch/dinner/snack, `recipe_id` *or* `title` — "leftovers",
  "takeout", "at Mum's" — `servings`, optional `cook_id`) is co-editable with
  the rest of the kitchen, and the Calendar draws the plan as a band the way
  it already draws a trip (D-trip-spine), for anyone the kitchen is visible
  to. A meal that really *is* an event (the dinner party, with guests and a
  time) is still an Event, and the plan row can link to it.
- **Live, because two people are in it at once.** Every kitchen write
  broadcasts on `[kitchen, :lists]` / `[kitchen, :pantry]` / `[kitchen, :plan]`
  over the Turbo Streams the tasks board already uses, so the item your
  partner adds at home appears on your phone in the store.

D-pantry's other half — that the match is arithmetic, not a model — stands;
D-food-catalog below changes only *what* the arithmetic joins on.

### D-food-catalog. A kitchen's foods are rows; the model files each new ingredient onto one once, and every match after that is a join.

Every feature in this plan joins three kinds of line — a recipe's ingredient,
a pantry item, a shopping-list item — on "is this the same food". D-pantry
answered that with `item_key`: `Recipes::Parse#key_for` strips descriptors,
lowercases, singularises. That is deterministic string normalisation, and as
a way of noticing that two lines were *typed the same* it's fine. As a way of
deciding what a line *is*, it's D-no-keyword-logic's word list by another
name — "AP flour", "plain flour" and "all-purpose flour" are three keys and
one food; "chicken thighs" satisfies a recipe's "chicken" and not the other
way round; and the failure is the silent kind that rule exists to prevent:
"what can I make" quietly misses the recipe because the fridge said
"scallions" and the recipe said "spring onions". D-pantry's aisle grouping had
the same problem more openly — "a small static table" mapping items to aisles
is a keyword classifier.

So the thing matched on is a row: **`foods`**, per kitchen.

```
foods           kitchen, name ("all-purpose flour"), aisle, default_location,
                kind_of_id (→ foods, nullable: "chicken thighs" → "chicken"),
                allergens (closed set), merged_into_id
food_aliases    food, key (the normalised item_key that resolved to it)
```

and `recipe_ingredients`, `pantry_items` and `shopping_list_items` each gain a
nullable `food_id`.

- **Resolution is a batched model call over a closed set** — the
  `Feeds::Classify` shape. `ResolveFoodsJob` collects the unresolved keys
  (new ingredients from a saved or imported recipe, new list and pantry lines),
  and asks once: *for each of these lines, which of these existing foods is
  it, or is it new — and if new, its aisle (from the aisle list), where it's
  kept, what it's a kind of (from the food list, one level), and which of the
  nine major allergens it is.* The answer is validated into the rows we have:
  an unknown food id is dropped, an aisle not in `Food::AISLES` is dropped, an
  allergen not in `Food::ALLERGENS` is dropped.
- **Ask about less.** A key is resolved once per kitchen, ever — the
  `food_aliases` row is the cache — so the second recipe that says "2 cloves
  garlic" costs nothing. A household's catalog settles into a few hundred
  foods; after the first month almost every new line is an alias hit, and the
  model sees only the genuinely new.
- **The user's corrections are rules, and rules are deterministic.** "These
  are the same" merges two foods (`merged_into_id`, aliases move); "this is
  in the Bakery aisle" edits the column. D-no-keyword-logic excludes the
  user's own explicit rules from its reach, and these are exactly that.
- **No model: exact matches only, and the page says so.** A key with no alias
  gets a food of its own named after it. Everything still works — lists
  merge, the fridge subtracts, "what can I make" ranks — over lines that were
  *typed the same*, which misses but never mis-matches. The fridge page
  carries one line: "Without a model, 'scallions' and 'spring onions' are two
  different things — merge them here, or connect a model." Aisle grouping is
  off (one list, in the order added) rather than guessed.
- **Allergens are the one field with teeth,** and are treated that way: a
  food's allergens are shown on the food and editable, a recipe's are the
  union of its foods', and the suggester only ever uses them to *exclude*.
  The app never tells anyone a dish is safe — only that it found a listed
  allergen in it, and it says "check the packet" beside every allergen
  mention, because a model-filed "contains: tree nuts" is a prompt to look,
  not a label.
- **The catalog is vocabulary, not content,** so it belongs to the kitchen
  rather than to anyone's private data — but a food's name can still say
  something ("prenatal vitamins"). The catalog page lists only foods reached
  through a row the viewer can see, so a food only one member's private
  recipe mentions is not on the shared kitchen's catalog page. Recipes are
  user-owned while foods are kitchen-owned, so a recipe's ingredients resolve
  against the **viewer's** kitchen at match time via `food_aliases` — not
  against a `food_id` frozen on the ingredient row. (The `recipe_ingredients.
  food_id` column is a cache for the recipe owner's own kitchen only.)

### D-food-suggestions. The ranking is arithmetic over foods; the model chooses among the top few and says why.

This is D-pantry's rule restated over `food_id` and extended to the three
suggestions the user asked for. Each is a query first and a sentence second:

1. **What can I make** — for every visible recipe, the fraction of its
   non-optional, non-heading ingredients whose food (or whose food's
   `kind_of`) is in the kitchen. Tiers: *ready*, *missing 1*, *missing 2*.
   Tie-break by the soonest-expiring pantry item it uses, then by
   `last_cooked_on` ascending (the rut-breaker). That list *is* the feature.
2. **Use it up** — the same query, filtered to recipes that use at least one
   pantry item expiring in the next N days, sorted by how many such items they
   use.
3. **Buy to unlock** — the user's second ask: "what should I buy so that what
   we already have gets used." For each food *not* in the kitchen, count the
   recipes it would move from *missing 1* to *ready*, and from *missing 2* to
   *missing 1*, weighting recipes that use expiring items. A greedy pass picks
   the next food, recomputes, picks again — a set-cover approximation over a
   few hundred recipes that runs in milliseconds in Ruby. The output is a
   short list — "buy coriander, limes and a tin of coconut milk and you can
   make 6 more things, 3 of which use the spinach" — each with an "Add to
   list" button.
4. **Plan the week** (a plan tool) — constraints in (nights, who's home from
   the calendar, time available, the kitchen's diners' exclusions, "use what
   we have"), candidates from queries 1–3, the model arranges them into
   `meals` rows as a *draft* the user accepts (D-agent-prepared-work: nothing
   lands before the click). The list for the week is then one button.

With a model, each surface gets a lead sentence and a pick ("the chilli — you
have everything but coriander, and the mince is oldest") and can propose a
swap ("no buttermilk: milk and a squeeze of lemon"). Swaps are shown as the
model's suggestion, labelled, and never change the ranking — a swap the query
didn't find is a hint, not a match. With no model, every surface is still
there, as its ranked list.

The model is also allowed one thing the query can't do: **propose a recipe the
box doesn't have** ("nothing you've saved uses the squash — here's a
roast-squash soup"). That lands as a draft recipe with a "suggested by your
assistant" source, on the import review banner the import pipeline already
uses, and never enters the rankings until the cook saves it. Finding one on
the web is Q9 territory and stays out.

**Diners.** Exclusions come from somewhere the user wrote them down, never from
inference: a per-kitchen list of diners (household members plus free-text
people — "Grandma, Sundays"), each with allergens (the closed set) and a
free-text diet note ("vegetarian", "no pork"). The allergen set excludes by
join; the free-text note is handed to the model to honour, and when there's
no model it's shown above the list as a reminder rather than parsed.

---

## 3. Data model

```ruby
create_table :kitchens do |t|
  t.references :user, null: false, foreign_key: true   # owner
  t.string :name, null: false, default: "Home"
  t.timestamps
end

create_table :foods do |t|                 # unique (kitchen, lower(name)) among unmerged
  t.references :kitchen, null: false, foreign_key: true
  t.string  :name, null: false
  t.string  :aisle                         # Food::AISLES, nil when unfiled
  t.string  :default_location              # fridge / freezer / pantry
  t.references :kind_of, foreign_key: { to_table: :foods, on_delete: :nullify }
  t.json    :allergens, null: false, default: []   # Food::ALLERGENS subset
  t.references :merged_into, foreign_key: { to_table: :foods }
  t.timestamps
end

create_table :food_aliases do |t|          # unique (kitchen, key)
  t.references :kitchen, null: false, foreign_key: true
  t.references :food, null: false, foreign_key: true
  t.string :key, null: false               # Recipes::Parse#key_for output
  t.timestamps
end

create_table :pantry_items do |t|
  t.references :kitchen, null: false, foreign_key: true
  t.references :food, foreign_key: true    # nil until resolved
  t.string  :item, null: false             # as typed
  t.string  :item_key, null: false
  t.string  :quantity_note                 # "half a bag", "2 tins" — prose (Q-pantry-quantities)
  t.string  :location, null: false, default: "pantry"
  t.date    :expires_on
  t.date    :opened_on
  t.references :added_by, foreign_key: { to_table: :users, on_delete: :nullify }
  t.timestamps
end

create_table :shopping_lists do |t|
  t.references :kitchen, null: false, foreign_key: true
  t.string  :name, null: false             # "Weekly"
  t.integer :position
  t.timestamps
end

create_table :shopping_list_items do |t|
  t.references :shopping_list, null: false, foreign_key: true
  t.references :food, foreign_key: true
  t.string  :item, null: false
  t.string  :item_key, null: false
  t.decimal :quantity, precision: 10, scale: 3
  t.string  :unit
  t.string  :note                          # "the big tub", "for Saturday"
  t.references :recipe, foreign_key: { on_delete: :nullify }   # "for: chilli"
  t.references :added_by, foreign_key: { to_table: :users, on_delete: :nullify }
  t.datetime :checked_at
  t.references :checked_by, foreign_key: { to_table: :users, on_delete: :nullify }
  t.timestamps
end

create_table :meals do |t|                 # index (kitchen, date)
  t.references :kitchen, null: false, foreign_key: true
  t.date    :date, null: false
  t.string  :slot, null: false, default: "dinner"
  t.references :recipe, foreign_key: { on_delete: :nullify }
  t.string  :title                         # when there's no recipe
  t.integer :servings
  t.references :cook, foreign_key: { to_table: :users, on_delete: :nullify }
  t.references :event, foreign_key: { on_delete: :nullify }    # the dinner party
  t.timestamps
end

create_table :diners do |t|
  t.references :kitchen, null: false, foreign_key: true
  t.references :user, foreign_key: true    # nil for "Grandma, Sundays"
  t.string :name, null: false
  t.json   :allergens, null: false, default: []
  t.string :diet_note
  t.timestamps
end

add_reference :recipe_ingredients, :food, foreign_key: { on_delete: :nullify }
```

- **`Kitchen`**: `Visible`, joins `AccessGrant::ITEM_TYPES`; not `Sectionable`
  (it *is* the Food section's place). `has_many` everything above,
  `dependent: :destroy`. `Kitchen.for(user)` finds-or-creates "Home".
- **Rows** (`PantryItem`, `ShoppingList`, `ShoppingListItem`, `Meal`, `Diner`,
  `Food`) have no `Visible` of their own: scoped through
  `Kitchen.visible_to(viewer)` in every controller, the album-contents pattern.
- **A line is a line.** List and pantry quick-add go through the recipe
  parser's line reader (quantity/unit/item/note), so "2 tins chickpeas" on a
  list and in a recipe become the same shape. Merging list items on add
  (same food, compatible unit → sum; otherwise a second line) is arithmetic.
- **Checking off is putting away.** `ShoppingListItem#check!(by:)` stamps it
  and, for items with a food, upserts a pantry item in the food's
  `default_location` — undoable from a toast for ten seconds, and turned off
  per kitchen for households that don't keep a fridge list. This is the
  single change that keeps a pantry list true without anyone maintaining it.
- **Using up is offered, not assumed.** "Cooked it" on a recipe opens a
  checklist of that recipe's foods currently in the kitchen, pre-ticked for
  the ones it uses a lot of; the cook unticks what's left over. No quantity
  subtraction until Q-pantry-quantities is answered.
- **Checked items age out.** Checked rows collapse under "In the basket"
  while shopping and clear off the list at the next midnight after the trip,
  kept for 30 days for "what did we buy last time" and the Money tie-in.

---

## 4. UX

### The Food hub (`/sections/food`, `Sections::Panels::Food`)

Top to bottom, most-used first, each zone collapsing to one line when empty:

1. **This week** — seven day-columns (a swipeable strip on a phone), each
   showing its planned meals as small recipe tiles; today's highlighted. An
   empty day is a "+" that opens the recipe picker (search, favourites, "what
   can I make" at the top). The "Share this kitchen?" card sits above it
   until answered.
2. **The list** — the default list, inline and live: a quick-add field (one
   line, paste many), items grouped by aisle, check-off in place. Other lists
   are tabs. "Open in-store view" goes full screen.
3. **In the kitchen** — expiring soon first (a coloured edge, never a
   percentage), then counts by location with a link to the full fridge.
4. **Ideas** — the three suggestion queries as three short rows: *Ready to
   make*, *Use it up*, *Buy to unlock*. Each is three items and a "more".
5. **Recipes** — a strip of recently cooked and favourites, "Open the
   recipe box" → `/recipes`.
6. **Tools** — Plan my week, What can I make (full page), and later the
   intake doors (§5).
7. The standard browse zone: everything tagged Food.

### The in-store list (`/kitchens/:id/lists/:id`)

The screen people will actually use most, and designed for one thumb in a
bad-signal aisle: large rows, aisle headers, tap anywhere on a row to check
it, checked rows slide into "In the basket" at the bottom. Who added what is
a small avatar on the row. The "for: chilli" note shows why it's there. Taps
are optimistic (the D-chat-optimistic pattern) and queue while offline, with
a quiet "3 changes waiting to sync" chip; full offline is Q-kitchen-offline.
The page keeps the screen awake while open (Wake Lock, where supported).

### The fridge (`/kitchens/:id/pantry`)

Three tabs — Fridge, Freezer, Pantry — each a list sorted by expiry then
name, with a quick-add that takes several lines. Each row: name, quantity
note, "opened 3 days ago" / "use by Thu", and a swipe (or a button) for
*Used up*, *Move to freezer*, *Add to list*. Adding by photo of a receipt or
a shelf is the intake door (§5).

### The plan (`/kitchens/:id/plan`)

A week grid (a day list on a phone) with slots down the side. Drag a recipe
between days; "Make the list for this week" adds every planned recipe's
ingredients — scaled to the meal's servings — to the chosen list, subtracting
what's in the kitchen, each line carrying "for: <recipe>". Re-running it is
idempotent: lines already added for that meal aren't added twice.

### The recipe page, joined up

The existing recipe page gains, owner or not: *In your kitchen: 7 of 9*
beside the ingredients (each ingredient marked have/need), *Add missing to
list*, and *Plan it* (pick a day). Nothing else on the page changes.

### Settings

The kitchen's own settings page (owner): name, sharing (the D-kitchen card),
diners, "checking off puts it in the fridge", the aisle order for your store
(drag to reorder `Food::AISLES`; a list ordered your way is a user rule), and
the foods catalog with merge/rename/edit.

---

## 5. How things get in (and the cross-section dividends)

The four doors, all landing through things already built:

- **Typing** — the quick-add fields above. One line, many lines, a paste.
- **A recipe** — "Add missing to list" / "Make the list for this week".
- **A photo** — a receipt or a shelf, through document intake
  (`docs/INTAKE_PLAN.md`): a new `Landing::PantryItem` kind declares its
  fields (item, location, quantity_note, expires_on), the model reads the
  image through the vision rung, and nothing lands without the review page's
  click. A receipt photo is the fastest honest way to stock a pantry after a
  big shop.
- **Email** — the grocery-delivery confirmation. `email_receipt` already
  recognises receipts; a grocery one becomes a suggestion "Put 23 items from
  your Tesco order in the kitchen?" that opens the same intake review.

Cross-section, free by construction:

- **Money** — the Groceries budget category is already watched by
  `budget_pace`; the hub shows "Groceries: $310 of $520 this month" as a one-
  line read when Money is on. Price estimates on a list are Q-grocery-prices.
- **Health** — an allergist's letter tagged Health + Food; diners' allergens
  are *written by the user* in the kitchen, never inferred from health data.
- **Pets** — `pet_food_reorder` gains "Add to list": the kibble reorder date
  already computed by D-pet-food-shelf lands on the kitchen's list as a line
  with "for: Rex".
- **People** — a meal can link to the Event it is (the dinner party), and
  that event's guests are the diners for that night.
- **Calendar** — the meal band (D-kitchen); the plan tool reads who's home.
- **Reminders** — "take the chicken out of the freezer" is a standing
  reminder the plan tool can offer to create for a planned meal whose food is
  in the freezer (`docs/REMINDERS_PLAN.md`).

---

## 6. Watchers (D20: deterministic triggers, model phrasing)

- **`pantry_expiry`** — items expiring in ≤ 2 days with at least one recipe
  that uses them: "The cream goes off Thursday — three recipes use it."
  Collapses a kitchen's same-day items into one suggestion. Retires when the
  item is used up, moved to the freezer, or the date passes
  (D-suggestion-lifecycle).
- **`meal_plan_gap`** — Sunday afternoon, when the coming week has fewer than
  N planned dinners and the kitchen has had a plan before: "Nothing planned
  from Wednesday — here are three you can make now." Off until the household
  has used the planner twice; never a nag for people who don't plan.
- **`list_before_shop`** — when a recurring "shopping" Event or reminder is
  within a day and the plan has meals whose ingredients aren't on the list
  and aren't in the kitchen: "Wednesday's shop is missing 5 things for this
  week's plan."
- **`recipe_rut`** — carried over from `RECIPES_PLAN.md` §5: the last eight
  weeks of `meals` + cook log are the same six dinners; here are three saved
  and never made.

All four register on `food` and respect its agent dial; at *Active*, the
expiry and gap suggestions can park a prepared draft (a list diff, a plan
diff) on the suggestion that lands on accept (D-agent-prepared-work).

---

## 7. Build waves

Each wave lands green (`bin/rails test`, `bin/rubocop`) and ships alone.

| Wave | Contents |
|---|---|
| **F1 — the section and the kitchen** | Food seed row + `AddFoodSection` migration; `Sections::Panels::Food` with the recipes strip and tools row; `Kitchen` (`Visible`, `ITEM_TYPES`, the "cook here" permission and its share-card wording, `Kitchen.for`, the share-this-kitchen card); `CategorizeRecipeJob` sees Food |
| **F2 — shopping lists** | `shopping_lists` + items, quick-add through the parser's line reader, merge-on-add by `item_key` (exact, pre-catalog), check-off, "In the basket", the in-store page, Turbo broadcasts, optimistic taps; recipe page "Add missing to list" (everything missing, until F4) |
| **F3 — the food catalog (D-food-catalog)** | `foods` + `food_aliases` + the `food_id` columns, `ResolveFoodsJob` (batched, validated, alias-cached), backfill for existing recipes, the no-model fallback and its line, the catalog page with merge/edit, aisle grouping + per-kitchen aisle order |
| **F4 — the fridge** | `pantry_items`, the three-tab page, quick-add, expiry/opened dates, used-up/move/add-to-list, check-off-puts-away, "Cooked it" use-up checklist, recipe page "In your kitchen: 7 of 9" |
| **F5 — the plan** | `meals`, the week grid and hub strip, drag between days, the calendar meal band, "Make the list for this week" (scaled, subtracted, idempotent), meal ↔ Event link |
| **F6 — suggestions (D-food-suggestions)** | Ready / Use it up / Buy to unlock queries and their hub rows and full page; diners + allergen exclusion; model picks, reasons, and labelled swaps; the draft-recipe proposal; the Plan my week tool |
| **F7 — watchers and doors** | the four watchers; `Landing::PantryItem`; grocery-receipt suggestion from `email_receipt`; pet food → list; the defrost reminder offer; the Groceries budget line on the hub |

F1–F2 are worth shipping alone — a shared, live grocery list is the single
most-asked-for household feature there is and needs neither a model nor a
catalog. F3 before F4 on purpose: the fridge is only as good as its matching,
and building it on `item_key` first would ship the silent-miss version of
"what can I make" and then rebuild it (the story-routing lesson).

---

## 8. Open questions (resolved 2026-09-23)

All four were answered the recommended way; the entries in `docs/decisions/`
carry the answers, and the paragraphs below are the reasoning. The three
calls flagged for pushback were also confirmed as designed: a kitchen share
always lets the grantee cook, meals are kitchen rows drawn as a calendar band,
and one share covers the lists, the fridge and the plan together.

- **Q-pantry-quantities.** v1 pantry items carry a free-text `quantity_note`
  and presence is the signal. Real quantity tracking (subtract 200 g flour
  when the bread is made) needs unit conversion and densities
  (Q-recipe-scale-units) and a household willing to keep counts true — the
  HOBBIES.md trap of making tracking the hobby. Decide after F4 has real use:
  do people want "running low" more than they want not to be asked?
- **Q-food-shelf-life.** Pre-filling an expiry date from a food would make
  the fridge far more useful with far less typing — but a model's guess at
  "how long does opened pesto last" is the confidently-wrong number this app
  refuses. The USDA's FoodKeeper data is public and would come in through the
  `datasets` layer, shown as "typically 5–7 days in the fridge (USDA)" and
  accepted into `expires_on` with a tap, never silently. Check its licence
  and coverage before committing; decide with F4.
- **Q-grocery-prices.** A list estimate ("about $84") wants prices. The only
  honest source is the household's own receipts — the Money ledger's grocery
  transactions and intake'd receipts — which would give per-food last-paid
  prices over time. Worth it once F7's receipt doors exist; not before.
- **Q-kitchen-offline.** F2 queues taps in memory; a lost connection plus a
  closed tab loses them. A real offline list needs a service worker and a
  merge rule for two phones that both went through a dead zone. Build only if
  the queue proves insufficient in real stores.
