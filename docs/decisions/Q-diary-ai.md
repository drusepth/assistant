<!-- open -->
**Q-diary-ai. When may the assistant read the diary?**
The highest-value corpus in the app and the strongest reason to say no. Structurally closed in v1: chat and tool turns execute in background jobs and key material never rides the queue, so no existing model surface *can* read entries. If it ever opens, the shape is fixed by `DIARY_PLAN.md` §8 — a per-user, off-by-default, D9-visible dial consenting to a specific act ("read my diary when I ask"), reads executed **in-request only** with the vault key from the cookie, never a standing context feed; mood inference and agent nudges from diary content never ship (D32). Gated on someone wanting it more than they fear it.

