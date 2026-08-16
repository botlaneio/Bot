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

### The test every signal must pass

**The signal must let you say something factual the recipient cannot dispute.**

"You've had this role open 71 days" passes. "I noticed you're using Kubernetes"
does not — it is an inference about what a company is *interested in*, not
evidence of what it is *failing at*, and it puts the opening line back to being
a guess. That is the thing this business exists to avoid.

### The hiring signals — all one story with different endings

Every one of these is the same underlying event: *they tried to solve an
infrastructure problem by hiring, and it did not work.* Only the ending differs.

| Signal | What it means |
|---|---|
| Role open 60+ days | Two months of losing candidates. The work still isn't getting done. |
| Quietly reposted | Same, plus an admission the first attempt failed. |
| **Contract or fractional role posted** | They have already accepted the work goes outside. You are not changing their mind, only their vendor. |
| **Posted, then removed with no hire announced** | Gave up, or froze budget. Weaker than a repost, same story underneath. |
| **Job title drift** | "Backend engineer (some infra)", reposted over months. They are trying to absorb platform work into existing roles and it is not holding. |

All five come from **one data source** and are computable from posting history
that is already being stored. That is why they are the build scope.

### Adjacent events — deferred, not rejected

Useful for *timing* rather than as the signal itself. Each needs a new data
provider and a new failure mode, so none is worth adding before the hiring
signals have proved themselves.

- **Engineering leadership change.** A new VP Engineering or CTO rebuilds their
  vendor list within 90 days. Genuinely strong — and the hardest to detect
  reliably. Best candidate if one is ever added.
- **Funding announced.** Scaling pressure with fresh budget. Widely used, so
  competitive: everyone with a Crunchbase feed hits them the same week.
- **Cloud partner tier change.** Relevant to the client's own positioning more
  than to their prospects'.
- **Public incident / status-page history.** Repeated outages do indicate real
  reliability pain. **Deliberately not used** — opening with someone's downtime
  reads as gloating, and the tone cost outweighs the signal.

### Excluded on principle

Website tech-stack changes, conference attendance, published infrastructure
content, GitHub activity, LinkedIn engagement.

All findable. All inferential. They reveal what a company is interested in, not
what it is failing at — so the opening line becomes a guess again.

## The service

1. Find those companies continuously across thousands of public job sources
2. Identify who owns the problem
3. Put the client's firm in front of them — from a **separate warmed domain, in
   the client's name and voice**
4. Route replies to the client within minutes; handle everything else
5. Weekly report: roles found, companies contacted, replies, meetings

**Pricing:** **$4,999 one-time setup**, then **$2,499/month** to maintain the
system. Everything included, cancel anytime. Or **$11,246** for setup plus the
first quarter prepaid (10% off).

The setup fee buys the thing that takes real work to stand up — the sending
domain, its authentication and warm-up, the signal tracking, the ICP and the
sequences. The monthly is what it costs to keep that running and to keep writing.
A client who stops paying the monthly keeps a system that was built; they stop
getting it operated.

> **Engineering consequence:** revenue is now front-loaded and the recurring
> figure is half what a pure retainer would have been. Four clients is
> ~$10k/month recurring rather than ~$20k, so the cost of serving each one
> matters more, not less. The maintenance tier must be genuinely cheap to run —
> that is an argument for the shared pipeline in *Where it goes*, not against it.

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

**Three to four clients on maintenance.** Four is also the hard cap, stated
publicly on the site — so it is a commitment, not an aspiration. Past four,
clients in the same niche start being shown the same companies in the same week.

Note the goal is four clients *still paying the monthly*, not four setup fees
collected. A setup fee is one-off revenue and flatters the number; the business
only exists if the systems stay running.

Every technical decision should be judged against: does this help one operator
land and serve four clients? If not, it is premature.
