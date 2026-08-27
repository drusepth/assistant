<!-- decided -->
**D-no-keyword-logic. Keyword and pattern matching is never how this app decides what something *is*. When the question is "what is this about", the model classifies — and if there's no model, the feature waits rather than guessing**
Twice now a feature has reached for a word list because a model call looked
expensive: story routing (D-story-matching, built on term lists and then
rebuilt) and the per-hobby vocabulary D-hobby-feeds §2 cut before it shipped.
Both were the same mistake, and the general rule is worth stating once so no
third branch has to rediscover it.

**A word list is a rule about an open subject.** It fails silently on
everything nobody thought to include, and silence is the worst failure mode
this app has: a hobby quietly missing half its stories looks exactly like a
hobby with nothing in it. Every guard such a mechanism needs — negatives, a
corpus test, a flood suspension, a per-term rejection tally — exists to patch
the fact that it cannot read.

**Matching is a worse classifier than the classifier we already have.** "Is
this story about birding" is a judgment. `bass` is not. An app whose whole
premise is that the household owns an assistant, doing substring comparisons
against headlines to decide what its user cares about, is telling on itself.

**So: classification is a model call**, batched, over a bounded set, with the
answer validated into a closed set of rows we already have (the shape
`Email::Triage`, `Feeds::Classify` and `Feeds::RouteStories` all share). The
way to make it affordable is to *ask about less* — a feed instead of its
stories, only the broad feeds' stories, once each, capped per run — never to
swap in a cheaper mechanism that answers a different question.

**What this does not cover.** Deterministic code is still deterministic:
parsing, dates, arithmetic, the user's *own* explicit rules (a `SpendingRule`
they wrote, an email sender rule they set), full-text search over their own
data, and format sniffing (is this OFX or CSV) are not classification and have
nothing to do with this. The line is: **is the app deciding what something is
about?** Then it reads it, or it waits.

**With no model configured**, such a feature is off and says so, rather than
falling back to a guess. That is a real cost — it used to be the argument for
keywords — and it is the right trade: a local model is the answer this project
recommends anyway, and a plausible-looking wrong answer is worse for a
self-hosted assistant than an honest absence.

**Known exception, to clean up:** `Spending::Categorize::KEYWORDS` files
transactions by merchant substrings before its model pass. It is narrower than
the cases above (a closed, hand-checked table of ~60 chain names, only ever
proposing standard category names, with the model as the next step), but it is
the same shape and should become a model-first path with the table as a
zero-token fast path only where the merchant string is an exact known chain.
