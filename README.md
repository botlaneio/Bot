# Bot

BotLane — repository for the BotLane outbound service, started 2026-08-12.

> **Status: sales and customer surface are live; the pipeline is not.**
> The repo holds the customer-account schema, the Stripe webhook Edge Function,
> and copies of the Framer code components. The ingestion pipeline — the only
> component with a hard time dependency — does not exist yet. The pipeline
> stack is undecided; see [CLAUDE.md](CLAUDE.md) and
> [docs/open-questions.md](docs/open-questions.md) for what is known versus
> open, and [docs/ingestion-recommendation.md](docs/ingestion-recommendation.md)
> for the draft recommendation (a proposal, not a decision).

## What BotLane is

A done-for-you outbound service for DevOps consultancies: BotLane finds US
companies failing to hire platform/SRE/infrastructure engineers (roles open
60+ days or quietly reposted), identifies the owner of that problem, and runs
outbound in the client's name from a separate warmed domain. $4,999 one-time
setup, then $2,499/month. The full definition is [docs/vision.md](docs/vision.md).

## Repository

| | |
|---|---|
| Remote | https://github.com/botlaneio/Bot |
| Default branch | `main` |
| Issue tracking | Linear — [botlanellc](https://linear.app/botlanellc) |

Layout:

- `docs/` — product definition, append-only decision log, open questions,
  session handoffs
- `supabase/` — customer-account schema migrations and the `stripe-webhook`
  Edge Function (the backend of the account area)
- `framer/` — copies of the Framer code components (`Account.tsx`,
  `MobileNav.tsx`). **Framer is the runtime**; these copies exist so the code
  is versioned and reviewable. Change one, change both.
- `scripts/` — stdlib-only research and build scripts (ATS date probes,
  sample builder)

## Getting started

There is nothing to run locally yet — no pipeline, no dependency manifest.
The Supabase migrations are applied to project `BotLane`
(`nekribxexmpmpzefcpvn`) and the Edge Function is deployed there. This section
gets written properly once the pipeline stack is decided and the first pipeline
code lands.

## Documentation

- [CLAUDE.md](CLAUDE.md) — operating instructions and technical context
- [docs/vision.md](docs/vision.md) — what BotLane is; the product definition of record
- [docs/decisions.md](docs/decisions.md) — append-only decision log
- [docs/open-questions.md](docs/open-questions.md) — deferred decisions and known risks
- [docs/ingestion-recommendation.md](docs/ingestion-recommendation.md) — draft Q1/Q2 recommendation (proposal, not decision)
- [docs/handoff.md](docs/handoff.md) — most recent session handoff
