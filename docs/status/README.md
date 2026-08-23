# docs/status/

One file per build-log entry. `docs/STATUS.md` holds the log through August
2026 and explains why this directory exists; everything after that lands here.

**Adding an entry** — create `YYYY-MM-DD-kebab-slug.md` (the date you're
writing it, a slug describing the work) containing the entry and nothing else:
one Markdown list item, same shape as the lines in `docs/STATUS.md`.

```
- **What changed, in a sentence (D-decision-slug; `docs/PLAN.md` §N)**: what
  it does, the choices that shaped it, and anything a future branch would
  trip over.
```

Rules, all of them consequences of "a new file can't conflict":

- **One entry per file, and a filename nobody else will pick.** The date
  prefix sorts the log; the slug keeps two branches on the same day apart.
  Never append your entry to an existing file — that's the shared line the
  directory exists to avoid.
- **Don't edit other entries.** They're a log, not documentation: wrong or
  superseded is what the next entry is for.
- **Read the whole thing with `bin/status`**, which prints `docs/STATUS.md`
  followed by this directory in filename order.
