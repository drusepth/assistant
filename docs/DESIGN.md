# DESIGN.md

The design language and where to change it. The stack is **Tailwind CSS v4**
(standalone binary via `tailwindcss-rails` — no Node) + **ViewComponent**.

## The look: Organic

Warm, rounded and a little playful — a cream-and-sand ground with a
terracotta accent and a sage second voice, Caprasimo display headings over
Figtree, and radii that grow into pills. Two rules carry most of it:

- **Surface sits *above* the canvas.** Cards are sand (`#ebddc5`) on a cream
  page (`#f5ead8`) — the inverse of a white-card-on-grey app. That tonal
  step is what separates a card, so cards need no border, and rows *inside*
  a card drop back to the canvas color.
- **Over-round, and don't crowd.** `rounded-full` for buttons, inputs and
  nav items; `rounded-2xl` for containers. The soft shapes need air to read
  as soft.

Warmth is the point: don't reach for stock Tailwind hues (`rose-`, `sky-`,
`amber-`), which read as foreign objects next to cream. Everything comes
from the two ramps. Overdue/urgent is *emphasis*, not error — it takes the
deep accent step (`primary-800`), leaving red for genuinely destructive
actions.

## The layers (each redesignable in one place)

1. **Tokens** — `app/assets/tailwind/application.css` `@theme` block.
   Brand ramp (`primary-*`), the sage second accent (`sage-*`), a warm
   neutral ramp (`stone-*`, overriding Tailwind's cool default), semantic
   neutrals (`canvas`, `surface`, `edge`, `ink`, `soft`), the type pairing
   (`--font-sans`, `--font-display`) and ink-tinted shadows. Changing these
   retunes the whole app — the ~500 uses of `primary-*`/`stone-*` across
   the views all resolve here.
   Both ramps are generated in OKLCH on one shared lightness scale, so the
   same step of any role carries the same visual weight: 100–300 tint fills
   and hovers, 500 is the base, 700–900 carry text on tinted fills.
   Headings pick up the display face from an `@layer base` rule, so views
   keep writing plain `<h1>`–`<h4>`.
   **Fonts are self-hosted** (`app/assets/fonts/*.woff2`), so a self-hosted
   app makes no third-party request to render its own text and works
   offline. Their `@font-face` rules live in
   `app/assets/stylesheets/application.css`, *not* in the Tailwind input:
   Propshaft digests asset filenames and rewrites `url()` only in the
   stylesheets it processes, and the Tailwind build is passed through
   untouched — a `url()` written there resolves undigested and 404s.
2. **Atoms** — same file, `@layer components`: `.btn` (+ `-primary`,
   `-secondary`, `-danger`, `-ghost`, `-alert`, `-now`/`-later`, `-sm`,
   `-touch`), `.input`,
   `.label`, `.hint`, `.field-error`, `.card`, `.chip`, the list-shape pair
   `.item-stack`/`.item-row` (+ `.stack-label`, see Lists), the two
   phone-shape atoms `.row-actions` and `.capture-row` (see Narrow
   screens), and the chat set — `.bubble` (+ `-user`, `-assistant`),
   `.composer` (+ `-input`, `-send`).
3. **Components** — `app/components/ui/*` (ViewComponent): `Ui::PageHeader`,
   `Ui::Card` (title/subtitle + actions slot), `Ui::EmptyState`, `Ui::Flash`,
   `Ui::SectionChip`, `Ui::Avatar` (a member's uploaded photo, falling back
   to their initials — every surface that names a person goes through it),
   `Ui::UserLabel` (that avatar plus a name, with the wording around the
   name as block content: "from Bea", "shared by Bea — read-only"),
   `Ui::QuickAdd` (header + button whose capture form
   drops down beneath it; needs an enclosing `data-controller="quick-add"`).
   Structural, slotted, reused everywhere.
4. **Forms** — `app/builders/application_form_builder.rb` is the default form
   builder app-wide. `f.field :title` renders label + input + errors with the
   system's classes; all input helpers pick up `.input` automatically.
   The section-tag picker is `app/views/shared/_section_picker.html.erb`.
5. **Item rows** — each primitive renders through its collection partial
   (`tasks/_task`, `events/_event`, …), so a list row is redesigned once and
   updates in every view that renders that primitive (index, section pages,
   Today, Dashboard).

## Section colors

Sections have stable identity colors, mapped in `SectionsHelper`
(`section_chip_classes` / `section_dot_classes`, keyed by top-level slug —
subsections inherit their parent's color). The seven are drawn from the two
Organic ramps rather than stock hues, each taking a distinct step so they
stay tellable apart at dot size, alternating terracotta and sage so
neighbours in the sidebar never collide: Health `primary-800` · Hobbies
`primary-500` · Education `sage-500` · Career `sage-700` · People
`primary-400` · Money `sage-400` · Rights `primary-700`.

## Lists

A card full of item rows has two shapes, and the choice is about how tall
the rows are rather than about taste:

- **`divide-y divide-edge`** — hairline dividers. Right for one-line rows
  (a document, a credential, an admin log line).
- **`.item-stack`** — each row drops back to the canvas colour and sits as
  its own rounded block with air around it, which is the "rows inside a
  card drop back to the canvas" rule carried to its end. Right when a row
  is several lines tall — a wrapped task title plus a meta line plus its
  buttons — because at that height a hairline stops separating anything and
  the card reads as one column of text. Today's lists are the reference.

Rows opt in by carrying `item-row` on their outer element (the primitive
row partials already do), so a `.stack-label` day heading can sit in the
same stack as plain text, and a row rendered into a `divide-y` list is
untouched by the stack rules. A card that stacks passes `padded: false` —
`.item-stack` brings its own padding.

`Ui::Card` also takes `count:` (a badge beside the title; zero doesn't
draw) and `anchor:` (an id plus the `scroll-mt` the sticky mobile top bar
needs), which is what lets a summary strip above a long page jump to the
card it counts.

## Narrow screens

The app is used on a phone at least as often as on a laptop, and the whole
page is 320–430 points wide there. Four rules keep it that way, and
`test/integration/mobile_layout_test.rb` pins the two that are mechanical:

- **Every `grid` names its base columns.** `class="grid gap-4 sm:grid-cols-2"`
  has *no* column definition at the base breakpoint, so it lays out in one
  implicit column — and an implicit column is `auto`, which sizes to its
  widest child rather than to the page. One card holding a long title then
  pushes the whole document sideways, and `truncate` inside it never fires.
  Write `grid grid-cols-1 gap-4 sm:grid-cols-2`: Tailwind compiles
  `grid-cols-N` to `repeat(N, minmax(0, 1fr))`, and the `minmax(0, …)` is the
  fix. Same story one level down — a flex child that must be allowed to
  shrink needs `min-w-0`.
- **`.row-actions`** for the buttons at the end of a list row. They ride
  beside the text on a wide screen and take their own full-width line on a
  phone; without it a 150-point cluster of actions squeezes the title it
  belongs to into a four-word column. The row that holds it needs
  `flex-wrap`. Give each button `.btn-touch` (and its form `flex-1
  sm:flex-none`) when it is an action people take by thumb: `btn-sm` is a
  28-point target, which is fine as furniture beside a title on a laptop
  and too small to hit on a phone. Label such a button with a drawn icon
  rather than a glyph — "→" inherits the display face at button size and
  all but disappears. When the row offers a *choice* rather than an action,
  colour the sides: `.btn-now`/`.btn-later` are the light tinted pair —
  accent for pulling something into today, the sage calm register for
  letting it wait — so the two are telling apart before either is read.
- **`.capture-row`** for one-line capture (a field and its submit): side by
  side when there is room, stacked on a phone so neither ends up half a line
  wide. Fixed field widths inside it belong behind `sm:` (`sm:w-32`).
- **Nothing that can't shrink.** `.btn` wraps its label rather than carrying
  `whitespace-nowrap`, and `.input` carries `max-w-full min-w-0` — a
  `<select>` sizes itself to its longest option, which is regularly wider
  than the phone it is on.

The check that matters is the page's own width: on a phone
`document.documentElement.scrollWidth` must equal the viewport width. Any
excess means something in the page is refusing to shrink.

## Conventions

- Views never hand-roll buttons/inputs/cards — use atoms and components.
- New shared visual patterns: promote to an atom (pure styling) or a
  `Ui::` component (structure/slots), then use it everywhere.
- Icons: `icon(:name)` helper (`IconsHelper`), inline Heroicons-style SVG.
- Chat: one surface, `tool_runs/_chat` (+ `_message`), rendered by both the
  run page and any page hosting a conversation. Assistant turns go through
  `chat_body` (`ChatHelper`) — a deliberately tiny markdown subset over
  escaped text; user turns are printed verbatim.
- Rebuild CSS with `bin/rails tailwindcss:build` (or `bin/dev` watches).
