# CLAUDE.md

Operating instructions and technical context for the BotLane repository.
Read this before acting. It records what is **verified**; anything not written
here is not established fact.

Last verified: 2026-08-12.

---

## 1. Project

**BotLane** — greenfield, started 2026-08-12.

**Product purpose: NOT YET DEFINED.** Do not assume one.

A previous iteration existed and was abandoned. Its tracker was reset on
2026-08-12 and its codebase is not present on this machine. For historical
reference only — **not a commitment for this repository** — that iteration was
described as "BotLane AI Operating System — Workflow Platform V1": a visual
workflow builder (canvas, nodes, edges, selection/overlay/interaction
frameworks, inspector, execution engine, AI nodes, integrations, natural
language builder, memory, monitoring, enterprise), built on a pnpm + Turborepo
monorepo with Next.js 15 and Tailwind v4.

Whether any of that carries forward is an open question. Treat it as prior art
someone described, not as this project's spec.

## 2. Repository

| | |
|---|---|
| Local | `C:\Users\neo\Desktop\neo\Bot` |
| Remote | https://github.com/botlaneio/Bot |
| Default branch | `main` |
| GitHub org | `botlaneio` |
| Linear workspace | [botlanellc](https://linear.app/botlanellc) |

**Current state: empty.** No application code, no dependency manifest, no build.
Only `README.md`, `CLAUDE.md`, `.gitignore`, and `docs/decisions/`.

The remote has not been verified to exist — GitHub CLI was not yet authenticated
at the time of writing, so `origin` is configured but unconfirmed.

## 3. Unknowns — do not invent

These are genuinely undecided. If a task depends on one, **ask** rather than
assuming, and update this file once decided:

- Product scope and vision for the fresh start
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
