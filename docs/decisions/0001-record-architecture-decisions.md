# ADR-0001: Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-08-12

## Context

BotLane is starting fresh. A previous iteration of the project kept its decision log
in Linear (issue BOT-24, "Decision Log (ADR) — BotLane TPM") and referenced ADRs by
number up to at least ADR-0010. That log lived outside the repository, so the
decisions did not travel with the code and were lost when the tracker was reset.

Decisions that shape architecture need to survive tracker resets, tool migrations,
and chat history. The repository is the only artifact guaranteed to persist.

## Decision

Architecture decisions are recorded as numbered Markdown files in `docs/decisions/`,
committed alongside the code they govern.

- Filename: `NNNN-short-kebab-title.md`, numbered sequentially from `0001`.
- Numbering restarts at `0001` for this repository. The old ADR-0001..0010 series
  belonged to the previous codebase and is not carried forward.
- Each ADR states **Status**, **Date**, **Context**, **Decision**, and **Consequences**.
- ADRs are immutable once Accepted. To change a decision, write a new ADR that
  supersedes it and update the old one's status to `Superseded by ADR-NNNN`.
- Statuses: `Proposed`, `Accepted`, `Superseded by ADR-NNNN`, `Deprecated`.

Linear may link to an ADR, but the file in this repository is the source of truth.

## Consequences

- Decisions are reviewable in pull requests, like code.
- Decision history survives resets of Linear, GitHub issues, or chat context.
- Writing an ADR is a small deliberate cost on every significant decision. This is
  intended: it is the mechanism that stops undocumented drift.
- Someone reading the repository cold can reconstruct why it is built as it is,
  without access to any external system.
