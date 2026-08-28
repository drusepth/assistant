<!-- decided -->
**D-about-pages. The /about pages are static software documentation, identical on every install, behind one household switch.**
The app explains itself to two readers: someone deciding whether to run it,
and someone already running it who wants to know what a feature does. Both
are served by one set of pages under `/about` — hubs for each area of life,
a page per feature, and a page per tool — rendered by the app itself rather
than by a separate marketing site, so the docs ship with the code and can't
drift from it.

Every one of those pages is **the same bytes on every install**. They
describe the software, never the household: no household name, no enabled-
section list, no item counts, no user data of any kind. That is what makes
the surface safe to expose at all — a stranger who loads `/about/features/
passwords` learns that the software has a password vault, which they could
equally learn from the public repository, and learns nothing about whether
*this* family uses it. Had the pages reflected local configuration, the
switch below would be a patch over a leak instead of a preference.

The switch is `households.public_pages_enabled`, admin-only, **default on**
— adoption beats elegance, and identical pages have nothing to broadcast.
It gates *unauthenticated* access only: a signed-in household member always
reads `/about`, because turning off the public site should not delete the
family's own documentation. When it is off, an anonymous request gets a
**404, not a 403** — a 403 confirms what it is meant to hide — and
`robots.txt` disallows the tree, since a static one would advertise the
paths the switch was flipped to hide.

`/about` is the second unauthenticated read path in the app, after
`/s/:token` (D-share-link). It carries the same posture: its own bare
layout, no session, no navigation into the app beyond a sign-in link, and
no route that interpolates user input into a template lookup — every page
resolves through a registry of known slugs.
