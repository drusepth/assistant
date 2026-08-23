# CHAT_PLAN.md

Build plan for the **chat surface** (D29) — the one screen in this app that is
judged against software everybody already uses every day. Seven tools talk
through it (`tutor`, `check_in`, `money_coach`, `mock_interview`,
`find_my_next_move`, `what_do_i_say`, `task_chat`), and on a phone it is
currently the weakest surface in the product.

Decisions here are logged as **D-chat-shell**, **D-chat-optimistic**, and
**D-chat-stream** in `DECISIONS.md`. Open questions are **Q-chat-fullscreen**
and **Q-chat-voice**.

---

## 1. What we're building and why

Everything else in this app is a form, a list, or a card, and it is fine for a
form to feel like a website. Chat is different: the user's reference points are
iMessage, WhatsApp, Signal, and the ChatGPT app, all of which they used within
the last hour, all of which have had hundreds of engineer-years spent on the
sixty vertical pixels around the text box. A chat that is 80% as good as those
does not read as "80% as good" — it reads as broken, because every interaction
is measured against a muscle memory that the surface violates.

That matters more here than vanity would suggest. The target user (VISION: the
99% without an executive assistant) meets this app *on a phone*, and the chat
tools are where the product stops being a filing cabinet and starts being an
assistant — the tutor session, the money coach, the "what do I say to my
landlord". If talking to it is annoying, the mode-2 and mode-3 thesis never
gets tested, because nobody gets far enough in to test it.

So the bar for this work is not "improve the chat CSS". It is: **on a phone,
sending a message and reading a reply should feel indistinguishable from a
native messaging app.** Specifically —

- The composer is *always* under your thumb. Never scrolled to, never behind
  the keyboard, never below a footer.
- Your own message appears the instant you send it. Not after a round trip.
- The reply arrives progressively, so a twelve-second model call reads as
  "it's talking" and not as "it's broken".
- The screen is mostly conversation, not chrome.
- Nothing important hides behind `:hover`.

Deliberately **not** in this plan: voice input (Q-chat-voice), a global
"talk to the assistant anywhere" entry point, message editing, threads,
attachments in chat, and search across transcripts. Those are features. This
plan is about making the feature we already shipped feel right.

---

## 2. What's wrong today, precisely

Anchored in the current code so the fixes have addresses.

### 2.1 The chat is a card in a scrolling document, not a screen

`app/views/tool_runs/_chat.html.erb:26` puts the transcript in
`max-h-[calc(100dvh-20rem)] overflow-y-auto` inside a `Ui::CardComponent`,
inside `main`'s `px-4 py-6`, below a sticky mobile header *and* a
`Ui::PageHeaderComponent`, above a recap footer.

That is **two nested scrollers**, and it produces every symptom in the report:

- You must scroll the *page* to reach the composer, then scroll the
  *transcript* to read. The two fight; on iOS, overscrolling one chains into
  the other and into the browser's own pull-to-refresh.
- `20rem` is a guess. It is wrong on a 667pt SE and wrong on a 932pt Pro Max,
  and it is measured against `dvh` while the actual chrome above it varies
  with the page header's content.
- The composer's position depends on scroll state, so "type the next message"
  is a two-gesture operation. In a native messaging app it is zero.
- `min-h-72` plus `max-h-…` means the card's height changes as the transcript
  grows, so the composer *moves* between turns.

### 2.2 Sending costs a full page round trip

`ToolRunMessagesController#create` ends in `redirect_to run`, which Turbo
morphs the whole page. Nothing at all happens on screen between the tap and
the server's response — on mobile data that is a few hundred milliseconds to
a couple of seconds of a screen that looks like it ignored you. Then the
entire document re-renders to add one bubble.

### 2.3 The keyboard is unhandled

- The layout's viewport meta (`application.html.erb:5`) has no
  `interactive-widget=resizes-content`. Chrome on Android therefore resizes
  only the *visual* viewport, so anything pinned to the bottom sits **behind**
  the keyboard.
- `.composer-input` is `text-sm` — 14px. **iOS Safari auto-zooms any focused
  field under 16px** and does not zoom back out. This is, on its own, a large
  share of "feels wrong on iPhone".
- No `env(safe-area-inset-bottom)`: on a gesture-bar phone the bottom row sits
  under the home indicator.
- The textarea carries only `autocomplete="off"`. No `enterkeyhint`, no
  `autocapitalize`, no `autocorrect` — so the on-screen keyboard shows a
  generic return key and doesn't capitalize sentences.

### 2.4 Chrome eats the screen

On the reported screenshot the conversation gets a little over half the
viewport. Above it: browser UI, the app's sticky mobile header, the page
header (title + "Started August 23, 2026" + Delete + New session). Below it:
two wrapped rows of quick-reply chips, the composer, and a three-line recap
footer with a button.

### 2.5 Touch-invisible affordances

`tool_runs/_message.html.erb` renders each timestamp
`opacity-0 … group-hover:opacity-100`. There is no hover on a phone, so **a
mobile user can never see when anything was said.** There is also no way to
copy an assistant reply, which is the single thing people most want to do
with one.

### 2.6 The wait is a black box

`ChatTurnJob` broadcasts one `broadcast_refresh_to` when the whole reply is
finished. A long tutor explanation is ten to thirty seconds of three bouncing
dots. The model is producing tokens that whole time and we are throwing them
away.

### 2.7 Smaller cuts

- Draft persistence is `data-turbo-permanent`, which survives a morph but not
  a navigation — leave the page mid-sentence and the sentence is gone.
- `aria-live="polite"` over the whole log plus whole-page morphs means a
  screen reader can re-announce the transcript rather than the new turn.
- The `chat-scroll` controller carries an `autoScrolling` 500ms timer flag to
  keep its own smooth scrolls from being read as the user leaving the bottom —
  a workaround that a single-scroller layout plus a sentinel makes unnecessary.
- The jump-to-latest button is unlabelled beyond `aria-label` and doesn't say
  that something new arrived.

---

## 3. The decisions

### D-chat-shell. The chat surface has two layouts — `screen` and `panel` — and on a phone it is always `screen`.

The partial has two hosts today (`tool_runs/show`, and `tasks/show` under
"Talk it through"), and they want opposite things. A dedicated conversation
page should own the viewport: one scroller, composer welded to the bottom,
chrome cut to a compact bar. An embedded panel on a task page is a card in a
flowing document and must stay one, or it breaks the page around it.

So `_chat.html.erb` takes a `layout:` local — `:screen` or `:panel` (default
`:panel`, since embedding is the constrained case) — and the height rules live
in two atoms, `.chat-screen` and `.chat-panel`, not in per-view utilities.
`:screen` is a `dvh`-based flex column: `flex-1 min-h-0 overflow-y-auto`
transcript, composer as a non-shrinking last row. `:panel` keeps a bounded
`max-h` and flows.

The corollary is the interesting half: **an embedded chat panel is never good
on a phone**, because a card that is itself a scroller inside a scrolling page
is the exact bug we're fixing. So below `sm`, the task page's panel collapses
to an entry point — a "Talk it through" row that opens the conversation as a
full screen — and stays inline from `sm` up. That needs a GET route for a
conversation that may not exist yet (the run is created lazily on the first
message, D30), so `GET /tasks/:id/conversation` renders the screen layout with
`run: @conversation` possibly nil, exactly as the panel already does.

Chrome on `:screen` gets a chat-specific compact bar below `lg`: back chevron,
tool title, overflow menu holding New session / Delete / Save a recap. The
recap footer and the page header's action buttons fold into that menu on
mobile and stay where they are on desktop.

### D-chat-optimistic. A sent message renders locally before the server hears about it, and the server replies with an append, not a page.

Two changes, and they belong together.

**The client renders first.** On submit, the `chat-input` controller appends
a user bubble from a `<template>` in the partial, clears the box, drops the
thinking indicator in, and scrolls — all synchronously, before the fetch
starts. This is what makes the app feel instant, and it is the single highest
ratio of perceived quality to lines of code in the whole plan.

**The server appends.** `ToolRunMessagesController#create` responds with a
Turbo Stream that appends the persisted user message and the thinking
indicator instead of `redirect_to run`, and `ChatTurnJob` broadcasts an append
of the assistant turn instead of `broadcast_refresh_to`. The transcript stops
being re-rendered wholesale, so scroll position, keyboard state, and the
`aria-live` announcement all stay correct for free.

Reconciling the two is the only fiddly part, and it is solved with a
client-generated id: the optimistic bubble carries
`id="msg-<client_token>"`, the form posts that token, and the server's append
targets the same id — so Turbo replaces the placeholder rather than producing
a duplicate. A failed POST leaves the optimistic bubble in place, marked
"Not sent", with a retry that re-submits it and **the user's text never lost**
— which is strictly better than today, where a failure loses the draft.

Non-JS keeps working: the form still posts normally, and a request that isn't
a Turbo Stream still gets the redirect. The optimistic path is an enhancement
layered on a working form, the same posture as the send button's dimming.

### D-chat-stream. The reply streams token-by-token, buffered, and degrades to today's behavior when the endpoint can't.

`Llm::Client#chat` gains a streaming mode (`stream: true` with an SSE reader
over the same `Net::HTTP` we already own — no vendor gem, per D14). The chat
path only: every other tool in the app parses a complete JSON document and
has nothing to gain.

`ChatBase#reply!` creates the assistant `tool_run_message` row **empty and
first**, then fills it as deltas arrive. The transcript element for it is
targeted by id, so each flush is a Turbo Stream `update` of one bubble.

Two guardrails, both mandatory:

- **Buffer.** One broadcast per token would put thousands of messages per
  reply through SolidCable. Flush on a ~80ms timer or a sentence boundary,
  whichever comes first.
- **Degrade honestly.** A custom endpoint that doesn't support SSE, or
  returns a non-stream content type, falls back to the existing single-shot
  call and the bouncing dots. Streaming is a nicety; a self-hosted Ollama on
  someone's laptop must not be broken by it. The provider picker gains no new
  question — we detect, we don't ask.

A failure mid-stream keeps whatever arrived and appends the existing notice
row, so a truncated reply is visible rather than vanished — the same posture
`ChatTurnJob` already takes.

---

## 4. The waves

Each wave lands green and independent, and each is worth shipping on its own.
W1 and W2 together are the bulk of the felt improvement; W3 is polish that
users notice without being able to name; W4 is the wow. W6 and W7 came out of
a second pass over the code rather than the screenshot, and W6 in particular
is not polish — it is a missing floor, and it should probably ship alongside
W1.

### W1 — The shell (the big one) — **built**

The layout fix, and the mobile platform basics that no amount of layout work
substitutes for.

- `_chat.html.erb` takes `layout:`; `.chat-screen` / `.chat-panel` atoms added
  to `app/assets/tailwind/application.css` beside the existing chat set.
- `tool_runs/show` renders `:screen`; `tasks/show` renders `:panel` from `sm`
  up and an entry-point row below it; `GET /tasks/:id/conversation` added.
- Compact chat top bar below `lg` on `:screen`, with the overflow menu
  (reusing the existing `popover` controller) taking New session, Delete, and
  Save a recap. `tool_runs/show` suppresses `Ui::PageHeaderComponent` for
  chat runs on mobile.
- `interactive-widget=resizes-content` on the layout's viewport meta.
- `.composer-input` goes to 16px on touch (`text-base sm:text-sm`), and the
  composer row gains `pb-[env(safe-area-inset-bottom)]`.
- Textarea gains `enterkeyhint="send"`, `autocapitalize="sentences"`,
  `autocorrect="on"`, `spellcheck="true"`.
- `overscroll-behavior: contain` on the transcript so the browser's
  pull-to-refresh can't fire from inside a conversation.
- A `visualViewport` listener in `chat-input` for iOS Safari, where the layout
  viewport does not resize under the keyboard: track
  `visualViewport.height`/`offsetTop` and hold the composer above the keyboard.
  Guarded — no `visualViewport`, no listener, and the `dvh` layout still works.
- Quick-reply chips become one horizontally-scrollable snap row on mobile
  (`overflow-x-auto`, no wrap), and hide once the composer holds a draft.
- `chat-scroll` moves from scroll-math to a bottom sentinel +
  `IntersectionObserver`; the `autoScrolling` timer flag goes away.

**Done when:** on a 375pt phone, opening any chat tool shows the composer
without scrolling; focusing it does not zoom; the keyboard covers no part of
the composer on iOS Safari and Chrome Android; the transcript is the only
thing that scrolls; and `test/integration/mobile_layout_test.rb` gains a chat
case.

*Built*, with four corrections to the plan as written.

- **The height arithmetic belongs to the page, not the screen.** `.chat-page`
  is the viewport minus `--app-header-h` minus `--keyboard-inset`, and
  `.chat-screen` is `flex-1 min-h-0` inside it — which is what lets the desktop
  page header sit above the screen without pushing it out of the viewport. The
  first attempt sized the screen itself and the laptop page scrolled by the
  height of its own header.
- **`min-h-screen` on the layout wrapper had to go for a bleed page.** It
  stacks a full viewport *under* the mobile header, so the document scrolled by
  exactly the header's height — the second scroller the whole wave exists to
  remove. The wrapper is now the viewport minus the header, `overflow-hidden`.
- **The header height is a token**, `--app-header-h`, set on `:root` and read
  both by the header that has it and by the page that subtracts it. The
  `20rem` this replaces was a guess in one place; a second guess would have
  been no better.
- **The `chat-scroll` sentinel rewrite was dropped, and that bullet was
  wrong.** The `autoScrolling` flag is not a workaround for scroll-math: an
  `IntersectionObserver` on a bottom sentinel cannot tell "the reader scrolled
  away" from "content grew below them", which is the only thing the flag is
  for. The controller keeps its scroll-based pinning (and gained the anchor
  restore in W3 besides). The cheap half — `overscroll-behavior: contain` —
  shipped.

Two things went further than planned because the bug was app-wide rather than
chat's: the touch font-size rule covers `.input` as well as `.composer-input`
(iOS zooms on *any* field under 16px, so every form in the app had it), and it
is scoped to `(pointer: coarse)` rather than a breakpoint — a phone in
landscape is wider than `sm` and would have kept the bug.

### W2 — Instant send (D-chat-optimistic) — **built**

- `<template>` bubble + client-side append in `chat_input_controller`.
- Client token on the form; `ToolRunMessagesController#create` answers
  `turbo_stream` (append user turn + thinking indicator), keeps the redirect
  for non-stream requests.
- `ChatTurnJob` / `ChatBase` broadcast appends rather than
  `broadcast_refresh_to`.
- Failed send → "Not sent" state on the optimistic bubble, with retry, text
  preserved.
- Draft persistence to `localStorage` keyed by run (or by subject, for a run
  that doesn't exist yet), restored on connect, cleared on successful send.
- `aria-live` scoped so an append announces the new turn only.

**Done when:** tapping send paints the bubble in the same frame; no chat
interaction re-renders the page; killing the network mid-send loses nothing.

*Built* — with the middle clause deliberately unmet, and the plan wrong to have
asked for it. The server still answers with a redirect and the page still
morphs, because a turn changes more than the transcript (the composer's lock,
the quick-reply chips, the recap affordance, the retry button, the thinking
indicator), and replacing one morph with five targeted streams would have
traded a large regression surface for nothing the reader can see. What the
reader *can* see is the gap between the tap and the response, and that is
closed entirely on the client: the bubble is drawn, the composer cleared and
locked, and the reply's dots started, all before the fetch leaves.

The reconciliation is the part worth keeping. A `client_token` column carries
the id the bubble was drawn with; the form posts it, the server stores it, and
`_message` renders the real turn under the same id — so the morph *matches* the
two instead of removing one and inserting the other, and nothing flickers.

The ordering around Turbo is subtle enough to state: `submit` is the last point
at which the form can be stopped (for the offline path) **and** the last point
at which a field can still change, because Turbo captures the request body when
it constructs the submission. So the token is stamped on `submit` and the
composer is cleared on `turbo:submit-start`, after the body is taken. Clearing
it a moment earlier posted an empty message — found by driving the real
browser, invisible to every test.

Grouping is the one thing the client can't know, so a sent turn always draws
standing alone and settles into its group when the morph lands.

### W3 — The conversation reads like a conversation — **built**

- **Time dividers**: a centered date/time line when the gap between turns
  exceeds an hour, and a day line across sessions — the native pattern.
  Per-message timestamps stop depending on hover: tap a bubble to reveal its
  time (and keep the hover reveal on pointer-fine devices). — *Built, with the
  tap-to-reveal replaced by something simpler and better: on a coarse pointer
  the group's timestamp is **always** legible, and it stays hover-revealed on a
  fine one. A tap gesture whose only affordance is "try tapping" is not
  discoverable, and one line per group of turns is not clutter. The divider
  says the day only as precisely as it needs to — "Today · 2:45 PM",
  "Yesterday · 9:12 AM", "Tuesday · 8:30 PM", "12 August 2024 · 8:30 PM" — and
  the first turn on screen always carries one, because with a windowed
  transcript the top of the page is wherever the reader came in.*
- **Copy** on assistant turns — a small button on the bubble, always present
  on touch, hover-revealed on desktop. — *Built, riding the app's existing
  `clipboard` controller rather than a new one; it sits in the same footer line
  as the timestamp and follows the same quiet-on-a-pointer rule.*
- Failure and notice rows restyled as one system line with the retry attached,
  rather than a centered orphan button. — *Built.*
- Recap affordance: on `:screen` mobile it lives in the overflow menu; the
  three-line hint copy shortens. — *Built (the menu landed with W1).*
- Haptic tick on send where `navigator.vibrate` exists (guarded; iOS ignores
  it and that's fine). — *Built.*
- `text-size-adjust: 100%` in the base layer. — *Built. Worth stating what it
  is and isn't: the app already sizes everything in `rem`, so it honours the
  reader's own font setting; this only stops the browser adding a second,
  uninvited scaling on top. Genuine iOS Dynamic Type is a different and much
  larger problem, and this is not it.*
- The jump-to-latest pill gains an unread count ("2 new") and sits above the
  composer, inside the safe area. — *Built, and it turned up a cascade trap the
  rail had already hit once: adding an `inline-flex` utility beside `hidden`
  put two `display` utilities in the same layer, where the winner is decided by
  Tailwind's own property sort rather than by the order they are written — so
  the pill was permanently visible. The layout moved into a `.chat-jump` atom
  in `@layer components`, which cascades before utilities, and `hidden` wins
  again. Caught by looking at a screenshot, not by a test.*

### W4 — Streaming (D-chat-stream)

- `Llm::Client#chat(stream:)` — SSE reader, buffered flush, content-type
  sniffing, clean fallback.
- `ChatBase#reply!` creates the assistant row first and fills it; the
  thinking indicator becomes the empty streaming bubble.
- Buffered Turbo Stream `update`s targeting the message id.
- Mid-stream failure keeps partial text + notice.
- Test with a stubbed SSE body and with a non-streaming endpoint, so both
  paths are pinned.

### W5 — It's an app (optional, cheap)

`public/service_worker.js` already exists for push (D22) and the layout
already carries `apple-mobile-web-app-capable`. Adding
`public/manifest.json` (`display: standalone`, name, icons, theme color) and
linking it makes the app installable — which removes the browser's own URL bar
and tab strip, worth roughly 15% of the vertical screen in the reported
screenshot, on every page and not just chat. This is a handful of lines for
the largest single pixel win available.

Not in scope here: offline caching. The service worker stays push-only until
someone actually designs offline behavior for a database-backed app.

---

### W6 — Conversations you can get back to (D-chat-index) — **built**

`config/routes.rb:198` is `resources :tool_runs, only: %i[ show destroy ]`.
There is **no index**. The only route back into a conversation is a link
somebody remembered to hand-place — `sections/panels/_health.html.erb:94`
offers "pick it back up" for the last check-in, and that is the entire recall
surface in the app. Every other conversation is effectively write-once: you
have it, you navigate away, and it is unreachable until
`PruneChatTranscriptsJob` deletes it at ninety days.

Which is a strange thing to discover, because the continuity is *already
built*: `ToolRun#previous_recap` renders "Picking up from last time —" at the
head of a transcript. The app implements resuming a conversation and gives the
user no way to ask for it.

And it is the load-bearing gap for this plan's own premise. In every app the
opening section benchmarks against, **the first screen is the list of
conversations.** Ours doesn't have one.

- `GET /conversations` — chat-kind runs, owner-only, newest first, with the
  last turn as a preview line and a relative timestamp. Grouped or filterable
  by tool, because "my tutor sessions" and "my check-ins" are different
  drawers.
- The tool's own start page (`tool_runs/new`) leads with "continue where you
  left off" when recent runs exist, so starting `tutor` offers *calculus,
  Tuesday* before it offers a blank form.
- A sidebar entry, which is what makes the chat tools findable at all rather
  than reachable only from the section panel that happens to link them.

One route, one query, one view. It is the highest value-per-line item left in
this document, and it should probably ship with W1 rather than after it.

*Built.* Two refinements the design didn't anticipate: the list orders by the
**newest turn**, not by when the run was created (a correlated `MAX(id)`
subquery — a conversation you came back to today belongs above one you started
today and abandoned), and the preview line skips `notice` rows, because the
app's own "something went wrong, try again" is furniture rather than the last
thing anybody said. The filter row appears only once there is more than one
kind of conversation to tell apart.

### W7 — The turn belongs to the user — **offline built, the rest open**

Three places the surface currently takes control away, all of which native
messaging simply doesn't.

- **You cannot type while it is answering.** `_chat.html.erb` renders the
  send button `disabled: thinking`, and the composer is dead for the whole
  reply. No messaging app has ever done this, and it is worst in exactly the
  case the chat tools are for — the thought that arrives *while* you're
  reading. Fix: type freely; a message composed during a reply queues and
  sends when the reply lands.
- **You cannot stop a reply.** Today the wait is opaque, so there is nothing
  to stop. After W4 the user watches a wrong answer arrive with no brake,
  which is worse. Stop is table stakes for a streaming chat: abort the SSE
  read, keep the partial text, mark it stopped.
- **Offline is not handled.** W2's "Not sent, retry" is the floor. The
  polish version watches `navigator.onLine`, holds the queue, and sends when
  signal returns — phones lose signal in lifts, on trains, and in basements,
  which is where this app's users are.
  *Built*, and it landed ahead of W2 rather than after it, because losing what
  someone wrote is a worse bug than watching it appear slowly. A send with no
  connection is intercepted before Turbo sees it (Turbo's submit handler runs
  on the document in the bubble phase, so a `preventDefault` on the form wins),
  kept in memory and mirrored to `localStorage`, and drawn into the transcript
  as a dimmed bubble with its own Retry and Discard. It flushes on `online` and
  on the next `connect()`. The three outcomes are distinguished on purpose: a
  network failure keeps the message and waits, a 4xx is the server genuinely
  saying no (the run is gone, or isn't a live conversation) and marks that one
  bubble "Couldn't send" rather than spinning forever, and a success drops it
  from the queue — with a single `Turbo.visit` at the end of the flush, not one
  per message, to bring the delivered turns in and take the placeholders out.
  The queued text sits in `localStorage` in the clear; that tradeoff is named
  in the controller rather than left to be discovered.

### Folded into the earlier waves — **built**

Found on review of the code rather than the screenshot, and each belongs in a
wave that already exists rather than a wave of its own.

**Reduced motion — and it is app-wide (→ W1).**
`grep -rn "prefers-reduced-motion\|motion-safe\|motion-reduce" app/` returns
**nothing**. The chat is the app's most motion-heavy surface by a distance:
three dots bouncing indefinitely, a smooth scroll on every turn, and after W4
text arriving continuously. For a vestibular disorder that is the difference
between usable and unusable, and "the 99%" includes them. A base-layer
`@media (prefers-reduced-motion: reduce)` block plus `behavior: "auto"` in
`chat-scroll` when it's set. The chat is where it's worst, not where it's
only.

*Built.* One wrinkle worth writing down: the blanket rule is deliberately
**unlayered and last in the file**, because the cascade reverses layer order
for `!important` declarations — so an unlayered important sits *below* every
layered one, which is exactly the priority a floor wants. A component that
means to keep a motion opts out by marking its own rule `!important` inside
`@layer components`, which is what `.celebrate-banner` (landed on main while
this plan was being written, and the one place in the app that already handled
reduced motion) now does: without the opt-out the blanket would have flattened
its fade to nothing and the banner would have vanished before it was read.

**Three rendering bugs (→ W3).**

- `.bubble` carries no `overflow-wrap`. A long URL or code span in a reply is
  an unbreakable token that pushes the bubble past its `max-w-[85%]` and the
  page sideways — the exact failure `docs/DESIGN.md` § Narrow screens pinned
  everywhere else in the app, still live here because the offending string
  arrives from a model at runtime instead of from a view at build time.
- `chat_body` renders inline code but **not fenced blocks**. A tutor asked
  anything technical emits ```` ``` ```` and the transcript prints the
  backticks. Blocks need their own `overflow-x: auto` container, per the same
  rule.
- Long transcripts render whole (`run.tool_run_messages.ordered`, no limit).
  A hundred-turn tutor session is a hundred bubbles of DOM on a phone that may
  be five years old. Render the last ~40 with "load earlier" above, using
  scroll anchoring so loading doesn't jump the reader. — *Built.* Three notes.
  The cursor is the `(created_at, id)` **pair**, not the id, so paging back
  agrees exactly with the order `ordered` renders in — an id cursor would
  disagree the moment two rows share a timestamp out of id order. The seam
  (`#chat-earlier`) stays in the DOM once the history runs out, hidden and
  empty, because it is also the anchor each older batch is inserted *after* —
  so successive loads stack correctly without knowing about each other. And
  the anchoring is ours rather than the browser's: Chrome and Firefox have
  scroll anchoring for exactly this and Safari doesn't, so `chat-scroll`
  captures `scrollHeight`/`scrollTop` on the click and spends it when the
  batch lands. Both stream actions apply in one synchronous pass, so the
  MutationObserver fires once against the finished height — verified at 0px
  drift, with a named turn holding its exact offset across the load.

**The last five percent of feel (→ W3).**

- Consecutive same-role turns group: tighter spacing, one timestamp for the
  run. Today every bubble sits in a uniform `gap-4`, which is the single most
  reliable visual tell of a homemade chat. — *Built.* The transcript's gap
  became the spacing *within* a group (`gap-1`) and anything that stands alone
  adds its own `mt-3`, which is cheaper and less fragile than negative margins
  on the grouped ones. The bubble's **tail** — the one squared corner pointing
  at the speaker — moved out of `.bubble-user`/`.bubble-assistant` into its own
  atom and now lands only on the last bubble of a run, which is most of what
  makes three quick messages read as one utterance. A group breaks on a change
  of speaker, on a five-minute silence (yesterday's last word and today's first
  are not one utterance), and on a notice from either side.
- `.bubble`'s `max-w-[85%]` gets a `ch`-based cap too, so a reply on a wide
  desktop card isn't a 120-character line. — *Built (`min(85%, 46ch)` from `sm`
  up; measured at 338px of a 704px card).*
- `chat_input_controller`'s `pointer: coarse` test treats a tablet with a
  keyboard attached as touch, so Enter never sends there. Detect the
  keyboard, not the pointer. — *Built, and the detection is **learned rather
  than guessed**: every media-query answer is wrong for some real device
  (`any-pointer: fine` would break newlines on a phone with a stylus), so a
  coarse-pointer device starts with Enter as newline and the first press of a
  key no virtual keyboard produces — Tab, Escape, a modifier, Home/End,
  PageUp/Down; arrows are excluded because some Android IMEs send them — flips
  it for good, remembered in `localStorage`.*
- Focus and announcement when the `:screen` layout mounts; `aria-live` held
  quiet *during* a stream and announced once on completion, so a screen
  reader isn't read the reply 80 milliseconds at a time. — *Deferred to W4 on
  purpose: there is no stream yet, and the second half of this is a rule about
  streaming. The composer already takes focus on a pointer device.*
- Respect the user's font scale in the transcript rather than pinning
  `text-sm` — the app's accessibility floor, exposed here first. — *Already
  true, and the bullet was wrong to imply otherwise: `text-sm` is `0.875rem`,
  which scales with the reader's browser font size. What was missing was the
  `text-size-adjust` guard above.*

### What cannot be tested from this machine

The phone-safe sweep drove a real Chromium at 320/375/414 and that is what
found the bugs. **None of W1's keyboard work can be verified that way**:
headless Chromium has no on-screen keyboard, no `visualViewport` offset, no
zoom-on-focus, and no safe-area inset. That half needs a real iPhone and a
real Android handset, and this plan says so out loud rather than letting a
green CI imply coverage it doesn't have.

## 5. Testing

The two mechanical rules go in `test/integration/mobile_layout_test.rb`
alongside the existing grid/overflow pins, since that file already exists to
stop phone regressions:

- A `:screen` chat renders exactly one scroll container.
- `.composer-input`'s base font size is ≥16px (a regression here is invisible
  on desktop and ruinous on iPhone — exactly what a pin is for).

System tests cover what unit tests can't: send with JS on → bubble appears
before the response; send with JS off → the form still posts and the redirect
still works; a failing turn leaves a retry and the user's text.

Streaming gets a stubbed SSE fixture in the client's own test, plus a
non-streaming endpoint asserting the fallback.

And the whole thing gets driven in a real 375pt Chromium the way the
phone-safe sweep was (`docs/DESIGN.md` § Narrow screens) — the mobile bugs in
this plan were all found by looking, not by testing.

---

## 6. Open questions

**Q-chat-suggested-replies.** The quick-reply chips are static per tool
(`ChatBase.quick_replies`), so the tutor offers "Quiz me" and "Show me an
example" no matter what was just said. Chips drawn from the actual turn would
be markedly better, and the cost is real: it conflicts with W4's plain-text
streaming, so it needs either a second cheap call per turn (latency and tokens
on every reply, on a self-hosted model that may be slow) or a trailing
sentinel line the app strips before rendering (fragile — a model that forgets
it costs nothing, a model that emits it mid-stream shows the user machinery).
Leaning sentinel-with-graceful-absence, decided after W4 exists. — *Not
started.*

**Q-chat-attachments.** "Here's a photo of the problem" is the most obvious
thing a phone user will try in the tutor, and "here's the letter" in
`what_do_i_say`. The primitives are there (Document, Photo) and so is the
plumbing, but it needs a vision-capable model — which most self-hosted
endpoints are not — so it needs the Q9 capability question answered first, and
it must degrade to something honest rather than silently dropping the image.
— *Not started.*

**Q-chat-fullscreen.** Should a chat on desktop also get a viewport-height
screen layout, or stay a card in the page? A tall desktop window makes the
card fine, and the app's other pages are cards; but a 900pt laptop showing a
chat card with a 200pt transcript is worse than a screen. Leaning: `:screen`
everywhere on `tool_runs/show`, `:panel` only where embedded. Decide by
building W1 and looking at it.

**Q-chat-voice.** Voice input is the single biggest mobile chat accelerant
after this plan's items, and `SpeechRecognition` on Chrome/Safari ships the
audio to a vendor — which is exactly the dependency this project exists to
refuse. A local Whisper is the honest version and is a real project. Parked
until someone asks for it, and if it lands it must say where the audio goes.
