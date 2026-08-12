# CLAUDE.md

Operating instructions and technical context for the BotLane repository.
Read this before acting. It records what is **verified**; anything not written
here is not established fact.

Last verified: 2026-08-12.

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
$2k–$4k/month retainers. Near-term goal is three to four of them.

Three facts that constrain nearly every technical decision:

1. **It is a service, not software.** Software exists only to let one person run
   it. The client never logs in. Do not build product surface.
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

**Current state: no application code**, no dependency manifest, no build. Only
`README.md`, `CLAUDE.md`, `.gitignore`, `.gitattributes`, and `docs/decisions/`.

Remote verified 2026-08-12: repository exists, public, `main` is the default
branch, and the authenticated account (`botlaneio`) has ADMIN permission. Local
`main` tracks `origin/main` and is in sync.

History begins with GitHub's auto-generated `Initial commit` (7f0ebcc), which
contained only a stub README. Local work was rebased on top of it rather than
force-pushed, so that commit is preserved.

## 3. Unknowns — do not invent

Product scope is now defined — see §1 and [docs/vision.md](docs/vision.md).

Three decisions were raised on 2026-08-12 and **deliberately deferred** until
environment setup is complete: ingestion approach, pipeline stack, and database
location. The options, tradeoffs, and recommendations are written up in
[docs/open-questions.md](docs/open-questions.md), along with three known risks
(Apollo credit ceiling, cold-email compliance, paused Supabase project). Read
that before reopening any of them — do not re-derive from scratch.

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
| Architecture decisions | `docs/decisions/` | local filesystem |

**GitHub access is via the `gh` CLI, not an MCP connector.** No GitHub MCP
connector is available in this Claude Desktop installation — the server appears
in the registry but exposes no tools. Use `gh` for repos, branches, commits,
issues, and PRs.

Until PATH refreshes (a Claude Desktop restart), invoke it by full path:
`"C:\Program Files\GitHub CLI\gh.exe"`

**The Linear MCP connector is read/write for issues and projects but cannot
delete them.** It exposes no `delete_issue`, `delete_project`, `delete_milestone`,
or archive tool. Deleting anything in Linear requires the user to do it in the
Linear web UI.

### External services (verified 2026-08-12)

Both are connected and authenticated as `admin@botlane.io`. Neither is yet used
by any code.

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

**Supabase** — project `Solo's System` (`fyofjbxukmovxvkdzuxf`), Postgres 17.6,
region `ap-northeast-1` (Tokyo). **Status: INACTIVE (paused)** — it must be
restored before use. Region was not chosen for this workload and is worth
revisiting before any data lands in it.

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

Record significant decisions as ADRs in `docs/decisions/` — see
[ADR-0001](docs/decisions/0001-record-architecture-decisions.md). The previous
iteration kept its decision log in the tracker, and lost it when the tracker was
reset. The repository is the only thing guaranteed to persist.
