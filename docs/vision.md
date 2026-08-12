# BotLane — Vision

Defined 2026-08-12. This is the product definition of record. Where code and
this document disagree, one of them is wrong — resolve it, don't route around it.

## What it is

A done-for-you outbound service for DevOps consultancies. One operator, run from
Bangalore, working US hours, serving US clients.

**It is a service, not software.** Software exists only to let one person run it.

## The customer

DevOps and platform engineering consultancies:

- 20–50 people, roughly $2M+ ARR
- US-based, services-only, no product line
- Buyer is the founder or the Head of Delivery

These firms grew on referrals, hit a plateau, and have no way to build pipeline.
Every hour their engineers spend on outbound is an hour not billed, and outbound
isn't a skill they can develop internally.

## The signal

When a company posts for a platform engineer, an SRE, or an infrastructure
engineer, and that role is **still open 60+ days later** — or gets **quietly
reposted** — they tried to solve the problem by hiring and failed.

That is the week a consultancy stops being a compromise and becomes the obvious
answer.

The signal is public, dated, and can't be argued with on a call. Most outbound
opens with a guess about a company's problems; this opens with a fact.

> **Engineering consequence:** this signal is *temporal*. "Still open after 60
> days" and "quietly reposted" can only be established by having observed the
> posting over time. It cannot be backfilled or bought. The clock starts the day
> ingestion starts running, and every day without it is signal permanently lost.
> This is the single strongest constraint on build sequencing.

## The service

1. Find those companies continuously across thousands of public job sources
2. Identify who owns the problem
3. Put the client's firm in front of them — from a **separate warmed domain, in
   the client's name and voice**
4. Route replies to the client within minutes; handle everything else
5. Weekly report: roles found, companies contacted, replies, meetings

**Pricing:** $2,000–$4,000/month, everything included, cancel anytime.

## How a client is won

Before anyone pays, BotLane sends them **40 companies in their own footprint
currently failing to hire infrastructure people** — role, days open, and the
person to contact. They keep it whether they hire BotLane or not.

Proof before payment, instead of case studies that don't exist yet.

> **Engineering consequence:** the 40-company sample is a *sales* artifact, not a
> client deliverable, and it is consumed before any revenue arrives. It must be
> cheap to produce per prospect. Anything metered — enrichment credits especially
> — is spent here at a loss and needs a deliberate budget.

## What it explicitly isn't

- **Not a guaranteed number of meetings.** Anyone promising that is pricing their
  uncertainty into the invoice.
- **Not a list you buy once.**
- **Not software the client has to learn and operate.** The client never logs in.
- **Not an agency.** It is one named person, stated openly, because a solo
  operator who answers directly beats an anonymous team on the things this buyer
  actually cares about.

## Where it goes

Every client sharpens the same shared system — signal detection, enrichment,
scoring, drafting, reporting — while **sending identity and client data stay
walled off per client**. Client four costs less to serve than client one.

When the same thing has been built four times over with barely any variation,
that repetition is the specification for a product. **Not before.**

> **Engineering consequence:** build for a shared pipeline with per-client
> isolation at the sending and data layer from the start, because retrofitting
> tenancy is expensive. But do **not** build product surface — no client-facing
> app, no self-serve, no configuration UI. The operator is the only user.

## Near-term goal

**Three to four retainers.**

Every technical decision should be judged against: does this help one operator
land and serve four clients? If not, it is premature.
