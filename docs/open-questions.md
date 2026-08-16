# Open questions

Decisions raised and deliberately deferred. Recorded so the reasoning survives
outside chat history. When one is settled, add it to
[decisions.md](decisions.md), remove it from here, and update `CLAUDE.md` §3.

Status: Q1 and Q2 remain open. **Q3 was settled 2026-08-16** — see
`decisions.md`.

---

## Q1 — Ingestion approach

**Question:** How do we detect the five hiring signals in
[vision.md](vision.md) — open 60+ days, quietly reposted, contract or fractional,
withdrawn with no hire, and job title drift?

**Option A — ATS APIs against a company watchlist** *(recommended)*

Poll public JSON endpoints for a curated list of US companies:

| ATS | Endpoint |
|---|---|
| Greenhouse | `boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true` |
| Lever | `api.lever.co/v0/postings/{company}?mode=json` |
| Ashby | `api.ashbyhq.com/posting-api/job-board/{name}` |

Also Workable, SmartRecruiters, Recruitee. Companies hiring infrastructure roles
skew heavily to the first three.

- Structured JSON, no HTML parsing, no rot
- Public APIs — no ToS conflict
- Posting dates included
- Inverts the model: maintain a bounded watchlist of companies rather than
  crawling the world. The watchlist becomes a core owned asset.

**Option B — broad job-board scraping** (as originally described)

Wider nominal reach, no watchlist to build. But: major boards actively block,
HTML breaks constantly, dates are often relative or missing, and maintenance
scales badly for a single operator.

**Assessment:** dates are the product. Option B degrades exactly the field the
whole business depends on.

### Four of the five signals are cheap. One is not.

Noted 2026-08-13. Four are **lifecycle events on a posting identity** — it
appeared, it is still open, it vanished, it came back, its employment type
changed. Each is answerable by storing a stable posting ID plus a few fields on
a schedule and diffing snapshots. No matching, no judgement, no model.

**Job title drift is a different problem.** "Backend engineer (some infra)"
appearing repeatedly over months is a *semantic* comparison across postings
where both the posting ID and the wording have changed. It needs fuzzy or
embedding-based matching plus a similarity threshold somebody has to tune — and
a threshold means false positives, which on this product means an opening line
that is wrong. The whole pitch is that the recipient cannot dispute the fact.

Two consequences:

1. **Sequence it last.** It shares a data source with the other four but not a
   mechanism. Letting it into the first build turns "computable from stored
   history" into "needs a matching model" before anything has shipped.
2. **It is company-level, not posting-level.** The claim is *"this company has
   posted N infra-flavoured backend roles over M months"* — an aggregation
   across postings, not a property of one. The schema should be able to express
   that from the start even though the signal ships later, because retrofitting
   a company-level rollup onto a posting-only store is the expensive kind of
   change.

This is an engineering inference, not a product decision — the signal itself is
in scope per `decisions.md`.

---

## Q2 — Pipeline stack

**Recommended: Python + Postgres.**

The workload is HTTP ingestion, fuzzy company matching, scheduling, LLM drafting,
and report generation — all Python's strengths. Python 3.13 is already installed.

TypeScript's main advantage is sharing types with a frontend, which is worth
nothing here: per `vision.md`, the client never logs in and no product surface
gets built before four clients.

---

# Risks

## R1 — Apollo credits don't cover the pre-sale motion

200 lead credits, 0 export credits. At 40 contacts per free sample, that funds
roughly **five prospect samples**, given away before any revenue. The pre-sale
offer consumes the scarcest resource first.

Needs either a top-up plan or a cheaper contact path for samples, reserving
Apollo for paying clients.

## R2 — Cold email compliance is unaddressed

Sending to US recipients, in a client's name, from a domain BotLane controls.
CAN-SPAM requires a valid physical postal address, a working opt-out honoured
promptly, and non-deceptive headers and subject lines. The "client's name, our
domain" model needs its sender identity to be accurate rather than misleading.

Decide and write an ADR **before the first send**, not after.

---

# Highest-value unknown to verify

**Do the ATS APIs expose original posting dates?**

`vision.md` states the signal is temporal and cannot be backfilled. That holds
for *reposts* — you must observe a posting disappear and return. It may **not**
hold for *age*: Lever exposes `createdAt` and Ashby `publishedAt`, which would
let "open 60+ days" be computed immediately. Greenhouse exposes `updated_at`,
which moves, and probably does need accumulated history.

**Unverified — field behaviour has not been checked against live responses.**

This is worth resolving first because it decides whether the first real
40-company sample is producible this week or only after two months of
observation — i.e. whether first revenue is days or months away.
