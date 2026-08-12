# Decisions

Append-only log. Newest at the bottom. A few lines each: what was decided, why,
and what it rules out.

Lives in the repository on purpose — the previous iteration kept its decision log
in the issue tracker and lost every entry when the tracker was reset. The repo is
the only thing guaranteed to persist.

Open decisions live in [open-questions.md](open-questions.md). When one is
settled, add it here and remove it from there.

---

### 2026-08-12 — Keep the decision log in the repo, as one flat file

Decisions go here, not in Linear and not in chat. One append-only file rather
than numbered ADR documents.

**Why:** the previous log lived in Linear (`BOT-24`, referencing ADR-0001 through
ADR-0010) and was destroyed when the workspace was wiped, while the code those
decisions governed would have survived. Numbered immutable ADRs with supersession
chains are a team-coordination format; this is a solo operation, so the ceremony
costs more than it returns. A flat log gets the durability without the filing.

**Rules out:** per-decision review workflow. If this ever becomes a team, revisit.

---

### 2026-08-12 — No speculative tooling

Rust/cargo, MSVC build tools, and Docker are deliberately not installed. Install
only when something concrete in this repository requires it, and say what.

**Why:** the stack is undecided. Installing a toolchain before knowing the
workload is guessing, and a wrong guess is dead weight that looks like a
commitment to whoever reads the repo next.

---

### 2026-08-12 — Product is a service, not software

BotLane is a done-for-you outbound service. Software exists only to let one
operator run it. No client-facing surface, no self-serve, no configuration UI,
until the same thing has been built four times over. Full definition in
[vision.md](vision.md).

**Why:** the buyer is explicitly not buying software they have to learn and
operate. Building product surface before four clients would be building against
a specification that doesn't exist yet.

**Rules out:** frontend framework decisions, auth, multi-user concerns, and
anything whose justification is "we'll need it when we productize."

---

### 2026-08-12 — LF line endings, enforced per-repo

`.gitattributes` pins `* text=auto eol=lf`, overriding the machine's global
`core.autocrlf=true`. Windows-native script types (`.bat`, `.cmd`, `.ps1`) keep
CRLF.

**Why:** the development machine is Windows but the pipeline will almost
certainly run on Linux. CRLF checkouts break shell scripts and git hooks, and
produce diff noise that hides real changes.
