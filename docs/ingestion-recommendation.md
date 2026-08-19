# Ingestion and pipeline — draft recommendation (Q1 / Q2)

> **ADOPTED 2026-08-18.** Q1 and Q2 were decided along these lines and the
> pipeline is built and running — see `decisions.md` (2026-08-18) for what was
> settled and `pipeline/README.md` for how it works. This document is kept as
> the reasoning that led there, not as a live proposal; where it and the code
> disagree, the code wins. Two things it did not decide were decided at build
> time: the scheduler (GitHub Actions cron) and the repository shape (flat,
> `pipeline/`). The LLM provider is still open.

**Status: draft, 2026-08-17. A proposal, not a decision.** This is the
operator's call to make and record in `decisions.md`, at which point the
matching entries come out of `open-questions.md` and `CLAUDE.md` §3 updates.

It is written against `open-questions.md`, which holds the full options and
tradeoffs; this document does not re-derive them, it recommends.

**Updated 2026-08-17 (second pass)** to fold in two findings that landed after
the first draft: the ATS date-fields question is **resolved** (all three
platforms expose an original posting date — `decisions.md` 2026-08-17), and
**Apollo's free plan has no API access** (`API_INACCESSIBLE` on every endpoint),
which changes the enrichment story and the sample sequencing.

---

## The constraints that decide most of this

From `vision.md` and `CLAUDE.md` §1:

1. **The signal is temporal and cannot be backfilled.** "Open 60+ days" and
   "quietly reposted" can only be established by having observed the posting
   over time. Ingestion is the only component with a hard clock: every day it
   is not running is signal permanently lost. Nothing else in this company is
   time-critical; this is.
2. **Dates are the product.** The entire pitch is "you've had this role open 71
   days" — a fact the recipient cannot dispute. Any mechanism that degrades the
   dates is disqualified, however much reach it offers.
3. **Cost-to-serve matters.** Revenue is now front-loaded ($4,999 setup) and
   recurring is ~$2,499/mo per client, so the shared pipeline with thin
   per-client isolation (vision.md, *Where it goes*) is an economic argument,
   not a taste one.

---

## Q1 — Ingestion: ATS APIs against a watchlist

**Recommend Option A** — poll public ATS JSON endpoints for a curated watchlist
of US companies. The case from `open-questions.md` holds and sharpens:

- Structured JSON, no HTML parsing, no rot; dates are included where the
  provider exposes them.
- Public APIs — no ToS conflict, no blocking arms race.
- It inverts the model: a **bounded watchlist** of companies rather than
  crawling the world. The watchlist becomes a core owned asset — it is the ICP
  made concrete, and it is what makes "40 companies in your own footprint"
  cheap to produce per prospect.
- **Lever board slugs are not guessable.** `eventbrite`, `kickstarter`, `quora`,
  `mixpanel` and `box` all 404'd while Greenhouse and Ashby slugs matched
  company names readily (learned 2026-08-17, `decisions.md`). The watchlist
  must therefore **store each company's discovered slug per ATS** — never
  derive it — which is one more argument for the watchlist being a first-class
  owned store rather than a list in a config file.

**The mechanism that makes four of the five signals cheap** (from
`open-questions.md`): they are **lifecycle events on a posting identity** —
appeared, still open, vanished, came back, employment type changed. Storing a
stable posting ID plus a few fields on a daily schedule and diffing snapshots
answers four signals with no matching and no model:

| Signal | Diff that produces it |
|---|---|
| Open 60+ days | provider's own posting date (`first_published` / `publishedAt` / `createdAt`) ≥ 60 days — computable on day one, no observation history needed |
| Quietly reposted | posting absent, then same identity present again |
| Contract / fractional | employment type field changes to contract |
| Posted, then withdrawn, no hire | posting absent, no hire announced |

One natural key — `(source, board_token, posting_id)` — plus a
`posting_snapshots` history is the whole store. This is the shape the pipeline
schema should have from the start.

### Original posting dates — RESOLVED 2026-08-17

The highest-value unknown from `open-questions.md` is settled — verified live
against eight public boards, no API keys. Full evidence in `decisions.md`
(2026-08-17); reproduce with `scripts/ats_probe.py` and `scripts/ats_probe2.py`:

| ATS | Field | Present on | Oldest seen |
|---|---|---|---|
| Greenhouse | `first_published` | **100%** (five boards, 510 postings) | 1347 days |
| Ashby | `publishedAt` | **100%** (three boards, 304 postings) | 1937 days |
| Lever | `createdAt` | present (epoch millis) | — |

**"Open 60+ days" is computable on day one.** At the moment of checking, 258
roles were already 60+ days old across five Greenhouse boards and 172 across
three Ashby boards. No two-month observation window for age.

**What remains temporal: reposts and withdrawals.** No snapshot shows a
posting disappear and return, so those signals still need accumulated history —
the ingestion clock still matters, just for a narrower set. `vision.md` was
right that the signal is temporal: right about reposts, wrong about age.

**Sequencing consequence:** the 40-company pre-sale sample can be built **this
week** from age alone, before any ingestion history exists. That was the
assumption the whole build order rested on; it is gone.

### Title drift: last, and company-level

"Backend engineer (some infra)" reposted over months is a *semantic* comparison
across postings where both the ID and the wording changed. It needs fuzzy or
embedding matching plus a similarity threshold somebody tunes — and a threshold
means false positives, which on this product means an opening line that is
wrong. The whole pitch is that the recipient cannot dispute the fact.

Two consequences from `open-questions.md`, endorsed here:

1. **Sequence it last.** It shares a data source with the other four but not a
   mechanism. Letting it into the first build turns "computable from stored
   history" into "needs a matching model" before anything has shipped.
2. **The schema must express company-level rollups from the start** (postings
   → organization), because the drift claim is an aggregation across postings,
   and retrofitting that onto a posting-only store is the expensive kind of
   change. A `postings.organization_id` column costs nothing now and saves a
   migration later.

---

## Q2 — Pipeline stack: Python + Postgres

**Recommend Python 3.13 + Postgres**, per `open-questions.md`, with Postgres
being the Supabase project already chosen for Q3 (2026-08-16).

Why Python: the workload is HTTP ingestion, snapshot diffing, scheduling, LLM
drafting and report generation — all Python strengths, and Python 3.13.15 is
already installed. TypeScript's one advantage — sharing types with a frontend —
is worth nothing here: per `vision.md` there is no product surface for the
pipeline to talk to, and the one customer-facing screen (the account area) is
already built against the database, not against the pipeline.

Why the existing Supabase Postgres rather than a new store: the database
decision is made, the project exists in `us-east-1`, and the pipeline's data —
watchlist, postings, snapshots, signals — is operator data with no tenancy
concern (the operator is the only actor). One project, a **separate `pipeline`
schema** to keep it out of the account-area schema; a separate database is
revisit-only-if-it-hurts. The account-area RLS rules do not apply here —
service-role writes are exactly how the pipeline would talk to it.

Component sketch (all deliberately boring, all replaceable):

| Piece | Shape |
|---|---|
| Pollers | one per ATS (Greenhouse, Lever, Ashby first), `httpx`/asyncio, daily |
| Store | `pipeline.postings` + `pipeline.posting_snapshots`, keyed on `(source, board_token, posting_id)` |
| Diff / signal detection | pure-Python snapshot diff → signal events |
| Scoring | rules, not a model, until the data justifies one |
| Enrichment | **Apollo has no API on the free plan** (`API_INACCESSIBLE` on `api_search`, `bulk_match`, `match`); contacts must come from public sources plus a verification step, or a paid data source — see R1 |
| Drafting | LLM provider API (provider choice is the operator's call) |
| Reporting | weekly email, assembled from signal events |

**Deliberately left open, not decided here:** the scheduler and host (deployment
target is an undecided §3 item — a small always-on Linux box with cron is the
obvious default but it is not this document's call), the LLM provider, and the
repository shape the pipeline code lands in.

**R1 sharpened, 2026-08-17** (`decisions.md`): the 200 Apollo lead credits are
real but **web-UI-only** — every API endpoint returns `API_INACCESSIBLE` on the
free plan, so there is no scripted enrichment at all, budgeted or not. The
contact half of the sample (company → named person) therefore comes from public
sources with a verification step — measured ~1-in-10 staleness on titles sourced
that way, too high to ship unverified — or from a paid data source. That is a
costed decision to make before the first sample ships; do not let a
bounce-prone guessed-email list ship under a brand whose pitch is precision.

**R2 carries straight over, and blocks the *sending* half, not ingestion:**
CAN-SPAM needs a valid physical postal address, a working opt-out, and accurate
sender identity. The postal address is recorded (2026-08-13 legal-identity
entry) but the compliance decision must be written before the first send —
nothing in this document changes that.

---

## Sequencing — status after 2026-08-17

**M1 (date-fields probe) — done.** All three ATS platforms expose an original
posting date (`decisions.md` 2026-08-17). Age is computable on day one.

**M2 — the first real sample — now the live work.** `scripts/build_sample.py`
starts it: board size as a size proxy plus an explicit too-big exclusion list,
pulling companies whose roles are already 60+ days old. The remaining piece is
the **contact half** (see R1) — a named person per company, from public sources
with verification or a paid source; that is the costed decision above. The
sample can ship this week as companies-and-roles; contacts decide whether it
ships complete.

**Still on the clock:** repost and withdrawal signals need accumulated history,
so the poller + snapshot store from Q1 is what the ingestion clock is for now —
start it regardless of the sample; it is the only thing that cannot be backfilled.

**Before any send:** the R2 compliance decision, recorded in `decisions.md`.

---

## What this document does NOT decide

Confirming the stack, the scheduler and host, the LLM provider, repository
shape, coding conventions, and roadmap milestones remain the operator's calls.
If work starts on the pipeline, ask before assuming any of them — `CLAUDE.md`
§3 is the list of things that must be asked about, and this draft changes none
of them.

---

## References

- `open-questions.md` — Q1/Q2 options and tradeoffs; R1, R2; the resolved
  date-fields question
- `vision.md` — the signals, the temporal constraint, cost-to-serve
- `decisions.md` — 2026-08-17 (ATS date fields resolved; Apollo API
  inaccessible), 2026-08-16 (database location, Q3), 2026-08-16 (account area
  schema), 2026-08-13 (legal identity)
- `scripts/ats_probe.py`, `scripts/ats_probe2.py` — live verification of
  posting dates; `scripts/build_sample.py` — first sample build
- `CLAUDE.md` §4 — verified environment (Python 3.13.15, no Rust/Docker)
