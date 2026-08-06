# VISION.md

## The problem

AI-driven automation threatens to sever the wage loop that capitalism's distribution depends on. Historically, mass displacement produced redistribution because labor had *leverage* (strikes, armies drawn from the working class). Full automation is the first scenario that removes the paycheck and the leverage in the same stroke — making a "technofeudal" equilibrium (capability owned by a few, everyone else outside the economy) potentially *stable* rather than self-correcting.

Waiting for governments or large companies to fix this has a perverse-incentives problem: the entities with the resources to provide AI assistance to the average person are the same entities whose business model is renting it. Bottom-up is the only alignment-safe direction.

## The single-builder theory of change

One person with no capital cannot out-capitalize labs or out-lobby incumbents. But code replicates at zero cost. The historical pattern (Linux, BitTorrent, Signal, Bitcoin): individuals shift power structures not by being the biggest player but by shipping **infrastructure with no owner, no chokepoint, and no off switch**. Policies can be repealed; deployed protocols with millions of users are facts on the ground.

The highest-leverage bet identified: **the local/owned-AI infrastructure layer**, because it's upstream of everything else — coordination tools, small-firm leverage, and household empowerment all inherit their independence from whether the underlying capability is owned or rented.

## What this project is

An open-source, self-hostable AI life-assistant website:

- **Model-agnostic.** We don't develop or integrate specific models; an open config lets users choose any local (or remote) model. Models are commodities; we build the layer around them.
- **The user owns the context.** The memory layer (documents, history, preferences, life data) is the real asset that makes assistance valuable. It must be local, portable, and inspectable — never on our servers, because there are no "our servers."
- **For the 99%.** The design question is: what do people with executive assistants, accountants, lawyers, and tutors get? That professional service stack is the requirements map — the mission is delivering it to everyone who has never had it.
- **Community-scaled.** Workflow packs let anyone publish domain expertise ("insurance appeal helper," "tenant rights assistant") as installable bundles. The ecosystem grows bottom-up; the core team doesn't build every vertical.

## Design values

1. **Adoption beats elegance.** The graveyard of liberatory tech is full of architecturally-correct, unused projects. The competitor is a frictionless, subsidized rented option. The bar is *better*, not "as good as": one-command install, usable by a non-engineer's nephew in an afternoon.
2. **Value without AI.** The Organize mode (owned life repository) must be independently useful. This de-risks model quality variance and builds the data foundation the AI modes need.
3. **Trust is earned, not assumed.** Proactive agent behavior comes last and is per-section user-controlled. The app proves it knows you before it acts for you.
4. **Privacy as a feature, not a policy.** Health, money, immigration status, disputes — the sections where the app helps most are exactly the ones where corporate data custody is most dangerous. Local-first is the product's deepest moat and its clearest pitch.
5. **Inclusive by default.** Voice-first access (local STT/TTS), household multi-user, plain language. Typing and jargon are filters that exclude the target audience.
