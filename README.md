# Assistant *(working title)*

An **open-source, self-hostable AI life assistant**. One household runs one instance; everyone's life information — appointments, tasks, documents, people, goals, notes — lives in a single, contained place *they* own, organized through section lenses (Health, Hobbies, Education, Career, People, Money, Rights) and assisted by whatever AI model the household plugs in.

Why: if AI assistance is only ever rented from a few large companies, its benefits concentrate there too. This project is infrastructure for owning the means of mental production — see [docs/VISION.md](docs/VISION.md).

## Documentation

- [docs/VISION.md](docs/VISION.md) — mission and strategy
- [docs/PRODUCT.md](docs/PRODUCT.md) — product design
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — schema and technical design
- [docs/DECISIONS.md](docs/DECISIONS.md) — decision log (entries in [docs/decisions/](docs/decisions/), read with `bin/decisions`)

## Development

Rails 8.1 · Ruby 3.3 · SQLite · Solid Queue/Cache/Cable · Hotwire. No external services required.

```sh
bundle install
bin/rails db:prepare db:seed
bin/rails test
bin/rails server
```

On first run, visiting the app walks you through creating your household and admin account. Invite the rest of your household from Settings — invitations are copyable join links, so no email server is needed.
