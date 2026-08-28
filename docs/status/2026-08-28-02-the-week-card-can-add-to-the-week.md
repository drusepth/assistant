**The week card can add to the week**: The Dashboard's "Next 7 days" card was
read-only — noticing a gap in your week meant scrolling back up to the hero's
capture keypad, which on a phone is a screen away. It now carries its own
`+ Event` beside the Calendar link, opening the same quick-add panel the hero
uses. Three small pieces made it fit:

- `Ui::QuickAddComponent` takes `small:`, the `btn-sm` shape for a
  `card.with_actions` row — quiet enough to sit beside the card's own links
  without out-weighing its title.
- `events/_quick_form` takes an optional `namespace:`, which prefixes the field
  ids and leaves the param names alone. The dashboard now draws that form
  twice, and two copies sharing `id="event_title"` would point every label at
  the wrong input.
- The `quick-add` Stimulus controller wraps the whole two-card grid rather than
  the one card that uses it: a wrapper around a single card would become the
  grid item, and the card inside would stop stretching to its neighbour's
  height.
