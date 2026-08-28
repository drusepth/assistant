**Suggestion rows drop their section chips**: The "From your assistant" card
on the Dashboard carried a section chip under every suggestion (Career,
Health, …). On a phone that chip was a third line of furniture between the
suggestion's own sentence and its buttons, and it said nothing the suggestion
didn't already say — "Book a health checkup" is not clarified by a Health tag.
Removed the chip row from `suggestions/_suggestion`, which also cleans up the
two section-scoped surfaces that share the partial (a section page's "Needs
your attention" card and the Education panel), where the chip was echoing the
page you were already standing on.
