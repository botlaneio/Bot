# Handoff — 2026-08-16

State of BotLane at the end of a long working session. Written so someone
picking this up cold — including a future me — does not have to re-derive it.

`decisions.md` is the reasoning; this is the position.

> **Correction, 2026-08-17.** The last line — "Uncommitted work: none.
> Everything through this session is pushed" — is no longer true. The working
> tree has `framer/MobileNav.tsx` modified beyond `HEAD` (d43ef91): the body
> scroll-lock now early-returns when closed and restores position via effect
> cleanup, and focus return uses a `wasOpen` guard. `docs/handoff.md` itself
> and `logo_green.png` are untracked. The "BLOCKED RIGHT NOW" section was not
> re-verified on this date; the fix sequence there still stands if the stale
> bundle persists.

---

## What exists

**BotLane sells two things.**

1. **The service** — outbound infrastructure for DevOps consultancies.
   **$4,999 one-time setup, then $2,499/month maintenance**, or **$11,246** for
   setup plus the first quarter. Invoiced at net 14, not card-on-file. Capped at
   four clients.
2. **The Marketplace** — individual automations, **$29–$399 one-time**, sold
   through Stripe Payment Links. Seven listed. **None has been built.**

Plus a **customer account area** at `/account` — invite-only, read-only.

---

## BLOCKED RIGHT NOW

**Framer is publishing a stale build of `MobileNav.tsx`.**

- The corrected source is in the Framer project. `readCodeFile` returns it, and
  the code editor shows no `react-dom` import.
- The published bundle `script_main.BzHRtlWc.mjs` still contains `createPortal`
  and no `overlayRef`. Framer's bundle filenames are content-addressed, so an
  unchanged hash means an unchanged build.
- Confirmed not a browser cache: a `cache: 'no-store'` fetch of the HTML names
  the same bundle, and that bundle fetched fresh still has the old code.
- Republishing produced no new bundle.

**Consequence: the mobile navigation is broken on the live site.** Below 1000px
the component renders nothing — 0×0 container, empty `<div>`, no console error.
There is currently **no navigation at all on mobile**, because the original
hamburger was deleted in favour of this component.

**To fix, in order:**

1. Edit `MobileNav.tsx` in the Framer editor by hand — type a character, delete
   it, save — to mark the project dirty, then publish.
2. If the bundle hash still does not change, paste the whole file in from
   `framer/MobileNav.tsx` in this repo and publish.
3. If neither works, restore a hamburger by hand so mobile has navigation while
   the sync issue is chased.

**Verification, one call:** fetch the published `script_main.*.mjs` and grep it.
`overlayRef` present and `createPortal` absent means the right code is live.
Checking the rendered page cannot distinguish "code is wrong" from "code is not
shipped" — that mistake cost several publish cycles.

---

## Live and taking money

**Stripe** — account `acct_1S1xniI9ZXWhlDED`. **Live mode only; the connector
exposes no test mode.**

| Product | Price | Product ID |
|---|---|---|
| Client Check-In Engine | $79 | `prod_V5BQzvbuNEJm5X` |
| Invoice Follow-Up Engine | $79 | `prod_V5BQ8yqzidD9p5` |
| Lead Response Engine | $149 | `prod_V5BPOVa2oNWPAV` |
| Content Repurposing Engine | $149 | `prod_V5BQunDCLWfT8Y` |
| Client Onboarding Engine | $149 | `prod_V5BQyjt43WQwAY` |
| Meeting-to-Action Engine | $149 | `prod_V5BQ7afwdQmfYw` |
| Executive Brief Engine | $399 | `prod_V5BQjoJPdNY1w1` |
| Outbound Infrastructure — Setup | $4,999 | `prod_V5Fz8abbkTn2MB` |
| Outbound Infrastructure — Maintenance | $2,499/mo | `prod_V5G0Ix2eqUPCDv` |
| Outbound Infrastructure — Setup + First Quarter | $11,246 | `prod_V5G0SGwlipe3hO` |

The seven Marketplace products have **live Payment Links that accept cards
now**. The three service products deliberately have none — the service is
invoiced to a named client.

Payment links are **card-only**, because dynamic payment methods are not
configured for USD on the account. Enabling them and recreating the links is a
real improvement.

**Supabase** — project `BotLane`, ref **`nekribxexmpmpzefcpvn`**, `us-east-1`,
org `sbeeayorpmyiybkyrqtv` (the **botlaneio** account).

> **There are two Supabase accounts.** Three abandoned projects exist across
> them — see `CLAUDE.md` §5. Before touching Supabase, check that the dashboard,
> the CLI and the Claude connector all point at `nekribxexmpmpzefcpvn`. They
> have disagreed before and it cost hours.

**Webhook** — `stripe-webhook` Edge Function, secrets set, Stripe destination
`we_1U56I0I9ZXWhlDEDBNinekNm` subscribed to seven events. Verified working by
signature rejection. **No real payment has ever flowed through it.**

---

## Test data that must be removed

One fake customer and its rows are in the production database:

```sql
delete from public.customers where email = 'denovosquareone@gmail.com';
```

Cascades handle two orders, two payments and one engagement. Remove before a
real customer exists.

---

## Outstanding, roughly in order of consequence

1. **Ingestion has not started.** `vision.md` calls the signal temporal and
   impossible to backfill: "every day it isn't running is signal lost." The repo
   has no pipeline code. Everything built so far is sales surface and customer
   surface. **This is the only thing with a clock on it.**
2. **Fix the Framer publish** (above). Mobile navigation is broken until then.
3. **Custom SMTP.** Supabase's built-in auth email is rate-limited to a handful
   per hour and is not for production. Magic link is the entire login path for
   the account area, so this breaks the front door under any real traffic.
4. **Seven live payment links for products that do not exist.** The listings say
   built-to-order and offer a full refund before delivery, and the Stripe
   checkout repeats it — but the first sale commits to building that automation.
   A Payment Link can be set `active: false` without deleting it.
5. **Verify the ATS date fields** — `open-questions.md` calls this the
   highest-value unknown, open since 2026-08-12. Whether Lever's `createdAt` and
   Ashby's `publishedAt` are exposed decides whether the first 40-company sample
   is producible this week or only after two months of observation. It is a few
   HTTP calls.
6. **Google OAuth** for the account area — needs a Google Cloud project and
   consent screen under the operator's account. Magic link works without it.
7. **`/terms` §11** caps liability at "fees paid in the three months before the
   claim arose", which is ambiguous now there is a large one-off setup fee.
8. **§12 governing law** still reads `[PROPOSED, NOT CONFIRMED]`.
9. **Panel width**: `maxWidth` 420 means the mobile menu is 47% at tablet
   widths, not the 75% asked for. Raise to ~600 if that matters.

---

## Constraints that cost real time to learn

**Framer**

- **Never import `react-dom`.** The component renders nothing, silently — 0×0
  container, no console error. Only `react`, `framer` and `framer-motion` work.
- Code files **cannot import each other**. A failed relative import registers
  *zero* exports and every instance renders blank.
- **Never diagnose layout from a node read as the root of a query** — that form
  returns absolute canvas coordinates and looks like a broken absolute layout.
  Read the node through its parent instead.
- `updateXmlForNode` returning **"No changes were made"** often just means the
  attributes already match. Confirm by reading through the parent.
- The NavBar's `MobileLight` is a **replica**; its children cannot be enumerated
  over MCP. Anything existing only in a mobile variant is invisible to an agent.
- `Actions` is the container the mobile variant hides. Putting anything mobile
  inside it makes it disappear on mobile.
- Site chrome lives in a **shared layout frame** (`j8u8AHMod`) that pages do not
  list. Edit it once for all pages; do not add per-page copies.
- Reads and writes only reach the **currently focused page or component**.
- **Judge pages by rendered HTML, never by page XML.**
- **Resizing the browser without reloading gives false readings** — Framer swaps
  breakpoint variants via SSR classes at load.
- Breakpoints: Desktop **≥1200**, Tablet 810–1199, Phone ≤809. The desktop nav
  needs only ~800px, so 1200 is far more conservative than necessary.

**Supabase**

- Run `get_advisors` after every schema change. It caught `SECURITY DEFINER`
  functions being exposed as REST endpoints.
- A project's region cannot be changed. Create a new project instead — cheap
  before data lands, a migration after.
- Test mode is not reachable through the connector.

**Stripe**

- `constructEventAsync`, never `constructEvent` — Deno's WebCrypto is async.
- Never construct a client at module scope in an Edge Function: a missing secret
  throws at boot and surfaces as an opaque `WORKER_ERROR` naming nothing.

---

## Repository

`github.com/botlaneio/Bot`, public, `main`. Docs plus `supabase/` (migrations
and the Edge Function) and `framer/` (copies of the Framer code components,
which are **not** the runtime — Framer is; change both together).

Uncommitted work: none. Everything through this session is pushed.

---

## Addendum, 2026-08-18 — the ingestion pipeline is live, and needs one secret to finish

Q1 and Q2 are settled and built (`decisions.md` 2026-08-18,
[pipeline/README.md](../pipeline/README.md)). Four migrations applied to the
live project, the poller is written, and the first real poll is in the database:
**8 boards, 41 postings, 34 already open 60+ days.**

### Three steps to hand over, in order

**1. Put the service_role key where the poller can find it.** Supabase →
project `BotLane` (`nekribxexmpmpzefcpvn`, botlaneio account) → Project Settings
→ API Keys → `service_role`. Add to `Bot/.env.local.txt`, which is gitignored:

```
SUPABASE_URL=https://nekribxexmpmpzefcpvn.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<the service_role key>
```

Nothing in this repository has ever held that key, and no session has seen it.
It bypasses RLS — never print it, never commit it.

**2. Finish the watchlist.** 98 boards were discovered across 86 companies; 8
are in. The rest go in with one command, which is also the end-to-end proof that
the HTTP write path works:

```bash
python -m pipeline.discover --slugs-file pipeline/watchlist_seed.txt --max-open-roles 120
```

**3. Start the clock properly.** Add the same two values as GitHub repository
secrets (Settings → Secrets and variables → Actions), then run
`.github/workflows/ingest.yml` once by hand (Actions → Daily ATS ingest → Run
workflow) to confirm it works before trusting the 13:17 UTC schedule.

### What is verified and what is not

**Verified:** the schema, the ingest function, and the lifecycle rules — six
assertions in `pipeline/tests/lifecycle_test.sql`, run against the live project,
including "a failed fetch closes nothing". The fetch and normalise path for all
three ATS platforms, against live boards. The first poll, whose rows are in the
database now.

**Not verified:** `pipeline/store.py`'s HTTP path — the RPC call over PostgREST
with the service_role key. It could not be exercised without the key, so the
first tranche was written through the database connector instead
(`pipeline/replay.sql` is that path, kept deliberately). Step 2 above is what
proves it. If it fails it will fail loudly on the first board, and the likely
cause is the grant, not the payload.

### Do not

- Do not let the poller run against a board list built by guessing slugs. Six
  words from a comment header turned out to be real ATS boards for unrelated
  companies. A wrong company here is not noise — it is a prospect list a client
  reads.
- Do not quote `days_open` from a posting where `days_open_is_observed` is true.
  That is our observation window, not the employer's date, and the entire pitch
  is that the number cannot be disputed.
- Do not add a Python dependency to make something here tidier. Stdlib-only is
  why there is no manifest, no install step in CI, and nothing to maintain.
