<!-- decided -->
**D-owned-lens. A lens a record owns says so on its row.**
D-pet-primitive put each pet's lens under People, so that "about Rex" is a tag every form, query and grant already understands. That placement was right, but nothing on the row said the lens was Rex's. "Is this a pet or a group?" was answered by asking the pets table from outside, so every surface that read People's children had to remember to ask. The ones that forgot kept treating the cat as a group:

- the panel lookup
- the tool flow-down
- the "Remove this group" button
- the People-page cards
- the person page's "Add to group" picker, which offered a vet made from the pet form "Add to group → Dimitri"
- the Address Book's group chips
- the membership endpoint
- `People::Group.find_or_create!`, which handed back the pet's lens when you made a group with the pet's name

Owned lenses also read as "People · Dimitri" on every chip and in the model's taxonomy listing, were listed as an area of People in Settings and onboarding, and disappeared from every form's picker when People was switched off.

So `sections.owner_type` is written when the owner creates the lens (`Sections::Lens.create!(…, owner_type:)`, validated against `Section::LENS_OWNERS`), and every question reads it:

- `Section.people_groups` is People's unowned children, the one definition of a group.
- `Section#subsections` is what a section lists as its own areas.
- `find_or_create!` and `named` only ever match unowned lenses.
- `qualified_name` qualifies an owned lens by its owner ("Pet · Dimitri"), not its parent. The same label reaches chips, page titles and the model's taxonomy.
- The section picker offers the viewer's own visible pets' lenses whatever People's toggle says, and never another member's private pet.

The lens stays under People. The alternative, a hidden parent just for pets, would have been a new kind of section every nav, settings and top-level listing had to learn to hide, for less than one column buys. — *Built 2026-09.*
