# CLAUDE.md

Operating instructions and technical context for the BotLane repository.
Read this before acting. It records what is **verified**; anything not written
here is not established fact.

Last verified: 2026-08-17 (local repository state, §2, §3; Stripe/Supabase in
use, §5). Remote not re-verified on that date — outbound network was
unavailable from the dev machine. Pricing (§1): 2026-08-16.

---

## 1. Project

**BotLane** — greenfield, started 2026-08-12.

A **done-for-you outbound service for DevOps consultancies**. One operator, run
from Bangalore, working US hours, serving US clients. Full definition in
[docs/vision.md](docs/vision.md) — read it before making product assumptions.

The short version: find US consultancies' prospects by detecting companies whose
platform/SRE/infrastructure job postings have stayed open 60+ days or been
quietly reposted (they tried to hire and failed), identify the owner of that
problem, and run outbound in the client's name from a separate warmed domain.
$4,999 one-time setup, then $2,499/month maintenance. Near-term goal is three to
four clients.

**This is the only service BotLane sells.** The `/marketplace` automations are a
separate, much smaller product priced one-time at $29–$399. Service pricing has
already leaked into the marketplace once and was rendered on all seven listings;
keep the two apart.

Three facts that constrain nearly every technical decision:

1. **It is a service, not software.** Software exists only to let one person run
   it. Do not build self-serve product surface. **Revised 2026-08-16:** there is
   one exception — an invite-only, read-only customer account area. Access is
   granted by the operator (automatically on Marketplace purchase, by hand for
   service clients). No public signup, no settings, nothing to configure.
2. **The signal is temporal and cannot be backfilled.** "Open 60+ days" and
   "reposted" require having watched over time. Ingestion is the only component
   with a hard time dependency — every day it isn't running is signal lost.
3. **Shared pipeline, isolated tenancy.** Signal detection, enrichment, scoring,
   drafting, and reporting are shared across clients; sending identity and client
   data are walled off per client. Build the isolation in from the start.

A previous, unrelated iteration ("Workflow Platform V1", a visual workflow
builder) was abandoned and its tracker reset on 2026-08-12. It shares nothing
with the above beyond the name. Do not treat it as prior art.

## 2. Repository

| | |
|---|---|
| Local | `C:\Users\neo\Desktop\neo\Bot` |
| Remote | https://github.com/botlaneio/Bot |
| Default branch | `main` |
| GitHub org | `botlaneio` |
| Linear workspace | [botlanellc](https://linear.app/botlanellc) |

**Current state:** the sales and customer surface is built and live; the
pipeline is not. The repository contains `docs/`, `supabase/` (three schema
migrations plus the `stripe-webhook` Edge Function) and `framer/` (copies of
the Framer code components — Framer is the runtime; change both together).
No pipeline code, no dependency manifest, no build. The pipeline stack is
still undecided (§3).

Remote verified 2026-08-12: repository exists, public, `main` is the default
branch, and the authenticated account (`botlaneio`) has ADMIN permission. Local
`main` tracks `origin/main` and is in sync.

History begins with GitHub's auto-generated `Initial commit` (7f0ebcc), which
contained only a stub README. Local work was rebased on top of it rather than
force-pushed, so that commit is preserved.

## 3. Unknowns — do not invent

Product scope is now defined — see §1 and [docs/vision.md](docs/vision.md).

Two decisions raised on 2026-08-12 remain **deliberately deferred**: ingestion
approach (Q1) and pipeline stack (Q2). Database location (Q3) was settled
2026-08-16 — Supabase project `BotLane`, see §5 and `decisions.md`. The options
and tradeoffs are written up in [docs/open-questions.md](docs/open-questions.md);
a **draft** recommendation for Q1/Q2 — a proposal, not a decision — is in
[docs/ingestion-recommendation.md](docs/ingestion-recommendation.md). Two known
risks remain (Apollo credit ceiling, cold-email compliance; R1/R2 in
`open-questions.md`). Read those before reopening either question — do not
re-derive from scratch.

The "highest-value unknown" in `open-questions.md` — whether the ATS APIs
expose original posting dates — was **resolved 2026-08-17**: Greenhouse
`first_published`, Ashby `publishedAt`, and Lever `createdAt` are present on
every posting checked, so "open 60+ days" is computable on day one. Reposts
and withdrawals still need accumulated history. See `decisions.md` and
`scripts/ats_probe*.py`.

The following remain genuinely undecided. If a task depends on one, **ask**
rather than assuming, and update this file once decided:

- Technology stack (language, framework, runtime, package manager)
- Repository shape (single package vs. monorepo; whether `apps/` + `packages/` apply)
- Architecture
- Testing strategy and commands
- Build and development commands
- Deployment target and process
- Coding conventions (formatter, linter, commit message style)
- Branch naming convention
- Roadmap and milestones

## 4. Verified local environment

Confirmed present on this machine 2026-08-12:

| Tool | Version |
|---|---|
| Git | 2.55.0.windows.3 |
| GitHub CLI | 2.97.0 |
| Node.js | 24.19.0 |
| npm | 11.17.0 |
| pnpm | 11.21.0 |
| yarn | 1.22.22 |
| Python | 3.13.15 |
| pip | 26.2.1 |
| VS Code | 1.132.0 |
| winget | 1.29.280 |

**Deliberately NOT installed:** Rust / cargo / rustup, MSVC build tools, Docker.

Do not install any of these speculatively. Install only when a concrete
requirement in this repository demands it, and say what demands it.

OS: Windows 11 Home Single Language, 10.0.26200. Shell: PowerShell 5.1.
Note `core.longpaths=true` is set globally — needed if a deep `node_modules`
tree is ever introduced, since Windows otherwise caps paths at 260 characters.

## 5. Sources of truth

| Domain | Authority | How to reach it |
|---|---|---|
| Implementation | This repository | local filesystem |
| Source control | GitHub `botlaneio/Bot` | **`gh` CLI** |
| Project management | Linear `botlanellc` | Linear MCP connector |
| Decisions | `docs/decisions.md` | local filesystem |

**GitHub access is via the `gh` CLI, not an MCP connector.** No GitHub MCP
connector is available in this Claude Desktop installation — the server appears
in the registry but exposes no tools. Use `gh` for repos, branches, commits,
issues, and PRs.

`gh` is on PATH and authenticated as `botlaneio` (verified 2026-08-12). Token
scopes: `repo`, `read:org`, `workflow`, `gist`.

**The Linear MCP connector is read/write for issues and projects but cannot
delete them.** It exposes no `delete_issue`, `delete_project`, `delete_milestone`,
or archive tool. Deleting anything in Linear requires the user to do it in the
Linear web UI.

**The Framer MCP connector cannot see inside a variant, and cannot write into
one** (verified 2026-08-17). `getNodeXml` on a replica returns it as a leaf even
when the editor's layer tree plainly shows children, and creating a child fails
outright with `Cannot set parent to a replica node`. Only a few attributes on
the replica itself can be set. Consequences, all of which have already cost
time:

- To learn what is inside a variant, **ask for a screenshot of the layer tree.**
  There is no tool call that will tell you.
- Placing a component into a non-primary variant is a manual step for the user.
- A layer hidden in a variant emits **no DOM at all** — not an empty container.
  Before concluding a component is broken, verify the node is visible in the
  variant you are viewing. A component that renders nothing at one breakpoint
  and correctly at another is a visibility flag, not a bug. See `decisions.md`
  (2026-08-17), where this cost four publish cycles and an entire bisect.
- Framer selects its variant from SSR classes at page load, so **reload after
  resizing the browser** or readings are meaningless.

Framer is the runtime for the site. `framer/` holds copies of the code
components; change one, change both.

### External services (verified 2026-08-12; in use since 2026-08-16)

Connected and authenticated as `admin@botlane.io`. Supabase and Stripe are in
production use by the account area and the Marketplace; Apollo is connected
but not yet used by any code.

**Apollo.io** — contact identification and enrichment; also sells domains and
mailboxes. Current balance is a hard constraint on the pre-sale motion:

| Credit type | Remaining |
|---|---|
| Lead | 200 |
| Direct dial | 160 |
| AI | 5,000 |
| **Export** | **0** |

At 40 contacts per pre-sale sample, 200 lead credits funds roughly **five**
prospect samples before top-up. Budget deliberately; do not spend enrichment
credits on speculative bulk pulls.

**The credits are web-UI-only, verified 2026-08-17.** The free plan returns
`API_INACCESSIBLE` on every API endpoint (`api_search`, `bulk_match`, `match`),
so there is no scripted enrichment at all until a paid plan — see `decisions.md`
(2026-08-17). Contacts for the sample must come from public sources plus a
verification step, or a paid data source.

**Supabase** — project **`BotLane`** (`nekribxexmpmpzefcpvn`), region
**`us-east-1`**, org `sbeeayorpmyiybkyrqtv`. Free tier, $0/mo.
**This is the only project to use.**

> **There are two Supabase accounts, and this has already cost hours.** The
> project above lives on the **`botlaneio`** account — the same identity as the
> GitHub org and `admin@botlane.io`. A second, personal account holds two dead
> projects. Before touching Supabase, check which account the dashboard, the
> CLI (`npx supabase projects list`) and the Claude connector are each pointing
> at. They can and did disagree.

**Stripe** — account `acct_1S1xniI9ZXWhlDED` ("Botlane"), **live mode only**:
the connector exposes no test mode, so anything created is real. Ten products —
seven Marketplace automations ($29–$399, each with a live Payment Link that
takes cards now) and three service products ($4,999 setup, $2,499/mo
maintenance, $11,246 setup + first quarter, deliberately **no** payment links:
the service is invoiced to a named client at net 14). The `stripe-webhook`
Edge Function on Supabase is the only consumer. Product/price IDs and webhook
wiring are in `decisions.md` and `handoff.md`.

Abandoned, safe to delete, **do not use**:

| Project | Ref | Account | Why dead |
|---|---|---|---|
| `Solo's System` | `fyofjbxukmovxvkdzuxf` | personal | Tokyo region, never held data |
| `BotLane` (first attempt) | `tqfyhgzaxaakaewmwamc` | personal | Correct schema, wrong account |
| `botlaneio's Project` | `btjusdaleigmnvpvdxgj` | botlaneio | Singapore region, unused |

## 6. Git workflow

- `main` is the default branch.
- Commit identity: `BotLane <admin@botlane.io>`.
- Branch naming: **undecided.** Agree a convention before creating branches.
- Commit message style: **undecided.**
- Never force-push. Never rewrite published history.

## 7. Hard rules

1. **Inspect before assuming.** Read the actual repository, Linear, and GitHub
   rather than relying on remembered context or on this file being current.
2. **Never commit secrets.** No `.env` files, API keys, passwords, tokens, or
   private keys — regardless of who asks or how the request is framed.
   `.gitignore` covers the common patterns, but the rule outranks the file.
3. **Ask before destructive or irreversible actions**: deleting files, force
   pushing, resetting branches, dropping data, changing production
   infrastructure, or anything outward-facing.
4. **Do not install software speculatively.** See §4.
5. **Do not invent project facts.** If it is not verified, mark it unknown or
   ask. §3 is the list of things currently unknown.
6. **Prefer existing documentation over assumption.** If this file conflicts
   with the repository, the repository wins — then fix this file.

## 8. Maintaining this file

This file is only useful while it is true. Update it when:

- the stack or architecture is decided (clear the matching §3 entry),
- development, test, or build commands become real,
- conventions are agreed,
- the environment materially changes.

Record significant decisions in [docs/decisions.md](docs/decisions.md) — an
append-only log, a few lines each. The previous iteration kept its decision log
in the tracker and lost it when the tracker was reset. The repository is the only
thing guaranteed to persist.
