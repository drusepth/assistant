**Pets hub leads with the pet card instead of an empty-state card**: the
reworded "Nothing filed about Rex yet" was still a "nothing here" under a pet
the user had just made. The generic browse-zone empty state is for sections
whose content *is* tagged items; on Pets the pets are the content, and each
pet's page is the way in. So `Sections::Panel#empty_state` became
`#show_empty_browse?` (Pets: only with no pets), and the pet card finally
carries the "honest invitation" `Pets::Cards` always promised — "Start with
his vaccines →" while no vaccination is on record, outranked by anything
booked, due, or a birthday, and gone once one is logged.
