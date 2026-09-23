<!-- decided -->
**D-section-picker. "Your life" sections get a picker page of their own — one card per top-level section, switched on or off one at a time**

(built). Choosing which sections a household uses used to be a column of
checkboxes inside the Settings page, saved together with the order and the
agent dials. That was fine while there were seven fixed sections. It stops
working once sections are something you pick from a list, like Pets, which
not every household needs, and later a catalog of packs. `/your-life`
(`LifeSectionsController`) shows every top-level section as a card with
the one-line blurb its /about hub already carries (no second copy), an
On/Off chip, and a single Turn on / Turn off button. That button saves
right away and redirects back to the same page, so Turbo morphs the page
and the sidebar row appears or disappears where you are. It writes the
same `user_sections.enabled` flag that Settings and onboarding step 1 write,
so the three can never disagree. Toggling leaves the agent dial and the
order alone. Turning a section off deletes nothing. The door in is a
"Customize" link beside the sidebar's Your life heading, and a "Choose
sections" row appears if every section is off. Onboarding step 1 already
asked this question, so it is not a new step. It now shows the same
blurbs. The catalog comes later, and it is this page with more cards.
