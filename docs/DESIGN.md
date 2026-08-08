# DESIGN.md

The design language and where to change it. The stack is **Tailwind CSS v4**
(standalone binary via `tailwindcss-rails` — no Node) + **ViewComponent**.

## The layers (each redesignable in one place)

1. **Tokens** — `app/assets/tailwind/application.css` `@theme` block.
   Brand ramp (`primary-*`) and semantic neutrals (`canvas`, `surface`,
   `edge`, `ink`, `soft`). Changing these retunes the whole app.
2. **Atoms** — same file, `@layer components`: `.btn` (+ `-primary`,
   `-secondary`, `-danger`, `-ghost`, `-sm`), `.input`, `.label`, `.hint`,
   `.field-error`, `.card`, `.chip`.
3. **Components** — `app/components/ui/*` (ViewComponent): `Ui::PageHeader`,
   `Ui::Card` (title/subtitle + actions slot), `Ui::EmptyState`, `Ui::Flash`,
   `Ui::SectionChip`, `Ui::QuickAdd` (header + button whose capture form
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
subsections inherit their parent's color). Health rose · Hobbies amber ·
Education violet · Career sky · People emerald · Money lime · Rights orange.

## Conventions

- Views never hand-roll buttons/inputs/cards — use atoms and components.
- New shared visual patterns: promote to an atom (pure styling) or a
  `Ui::` component (structure/slots), then use it everywhere.
- Icons: `icon(:name)` helper (`IconsHelper`), inline Heroicons-style SVG.
- Rebuild CSS with `bin/rails tailwindcss:build` (or `bin/dev` watches).
