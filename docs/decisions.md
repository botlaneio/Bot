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

---

### 2026-08-13 — Public price is $5,000/month, stated as one number

The landing page publishes a single flat price rather than the $2,000–$4,000
range previously in `vision.md`. `vision.md` and `CLAUDE.md` updated to match.

**Why:** a range anchors the reader at the bottom of it and turns the pricing
page into an objection to answer on the call. With a target of only four
clients, price discrimination buys very little and costs a story that has to
stay consistent between clients who operate in the same niche. Underpricing is
also hard to reverse — raising a price on an existing client is a conversation
nobody wins.

**Rules out:** tiered pricing and public discounts. Concessions, if any, are
private and per-deal.

---

### 2026-08-13 — Marketing site is built in Framer, not in this repo

The landing page lives in a Framer project. No site code lands in this
repository.

**Why:** the site is a sales artifact, not product surface, and the operator
needs to edit copy without a deploy. It does **not** decide the pipeline stack —
`CLAUDE.md` §3 stays open.

**Which project:** the one containing the `SignalMonitor.tsx` code component,
mono-first type (Geist Mono / JetBrains Mono) and semantic colour tokens
(`/Background/Base`, `/Branding/Accent`). Two pages: `/` and `/404`.

A second Framer project — a dev-tool SaaS template with `/Neutral/*` colour
tokens — was rebuilt against this brief earlier the same day and then
**abandoned** once the project above was found to be further along. Do not
resume work in it. Sections demanding social proof (press logos, testimonials,
invented metrics) were deleted rather than filled in both; the 40-company sample
carries the proof load instead, per `vision.md`.

**Open items on the live project:**
- The 4th "How it works" card is numbered `1`. Its number control rejects MCP
  writes (likely a number-type prop the plugin cannot marshal) — fix by hand.
- The `PricingPlans` component may still contain the old $2,000–$4,000 price
  internally. It exposes no props, so its contents are not readable over MCP.
- The hero email-capture form's backend wiring is unverified. If unconnected it
  silently discards submissions.
- No privacy policy or terms pages exist. The privacy page is part of the
  CAN-SPAM answer (see R1/R2 in `open-questions.md`) and is needed before the
  first send.

---

### 2026-08-13 — A quarterly prepay option at 10% off

$5,000/month stays the headline. A second billing option — **$13,500/quarter**,
a 10% saving — sits behind a toggle on the pricing card.

**Why:** partly cash timing. R1 in `open-questions.md` notes the 40-company
samples are given away at a loss before any revenue and that Apollo credits are
the binding constraint; a quarterly prepay funds that motion.

But the stronger reason is that a quarter is the first point at which the work
can honestly be judged. The sending domain takes weeks to warm, so a client
evaluating on thirty days is evaluating warm-up, not results. Quarterly is
therefore framed on the site as the honest window rather than as a discount.

**Supersedes** the "rules out public discounts" clause in the 2026-08-13 pricing
entry above. That still holds for *ad-hoc* discounting: the quarterly rate is a
published, uniform second option, not a negotiated concession.

**Not annual.** A twelve-month commitment would contradict "cancel anytime,"
which is load-bearing in the FAQ, the comparison table, and the pricing copy —
and it is the exact objection the comparison table raises against agencies.

**Open:** ~~the FAQ's cancellation answer has never been readable over MCP~~ —
resolved 2026-08-13. The bought FAQ component was replaced with a hand-built
list, and its cancellation answer now states both terms explicitly.

---

### 2026-08-13 — `/privacy` and `/terms` written, both carrying blockers

Both pages now exist on the site and are written specifically for this business
rather than adapted from a generic template — the privacy policy separates
*clients* from *people who receive outbound*, because the answers differ and
most templates conflate them.

**Neither is publishable as it stands.** Each carries bracketed placeholders,
deliberately left glaring rather than filled with plausible text:

- Legal entity name (both pages)
- **Physical postal address** — legally required in every marketing email under
  CAN-SPAM. This blocks the first send, not just the page.
- Governing law. The operator is in India, the clients are US-based; this needs
  a deliberate choice.
- Payment terms and grace period
- Sub-processors and enrichment providers, once the stack is chosen
- Whether Framer site analytics are enabled

**Neither has been reviewed by a lawyer.** They are drafted to be accurate and
readable, not to substitute for advice. R2 in `open-questions.md` called for
this to be settled before the first send; it is now drafted but not discharged.

---

### 2026-08-13 — Signal scope: hiring signals only, and the test they must pass

**The test:** a signal must let you say something factual the recipient cannot
dispute. "You've had this role open 71 days" passes. "I noticed you're using
Kubernetes" does not. Full taxonomy in [vision.md](vision.md).

**In scope — five hiring signals:** role open 60+ days; quietly reposted;
contract or fractional role posted; posted then withdrawn with no hire
announced; job title drift. All are the same event with different endings — a
hire that did not work — and all come from **one data source**, computable from
posting history already being stored.

**Why not more:** adding funding feeds or leadership-change detection means new
providers and new failure modes before the first source has proved itself. The
strongest deferred candidate is **engineering leadership change** (a new VP Eng
or CTO rebuilds their vendor list within 90 days); the hardest to detect, and
the one to revisit first.

**Ruled out permanently:** public incident and status-page history — opening with
someone's downtime reads as gloating, and the tone cost outweighs the signal.
Also tech-stack detection, conference attendance, published content, GitHub and
LinkedIn activity: all inferential, and each one turns the opening line back
into a guess.

**Closes Q4** in `open-questions.md`.

---

### 2026-08-13 — Legal identity, recorded

| | |
|---|---|
| Entity | **Botlane LLC** — Wyoming limited liability company |
| Registered address | Registered Agents Inc, 30 N Gould St Ste R, Sheridan, WY 82801 |
| Contact | sales@botlane.io · +1 754 279 3658 |

The registered address is now published in `/privacy` and the site footer, and is
the address that must appear in **every marketing email** under CAN-SPAM.

**Two things to be aware of:**

- That Sheridan address is a shared registered-agent address used by a very
  large number of Wyoming entities. It is legally valid and satisfies CAN-SPAM,
  but some spam-reputation systems treat it as a weak trust signal. Relevant
  because deliverability is precisely what clients are paying to protect.
- Governing law in `/terms` is set to **Wyoming** as a proposal, not a decision.
  It is the natural default for a Wyoming LLC serving US clients, but the
  operator is in India and this was never confirmed — the clause is marked as
  unconfirmed on the page.

**Resolved same day:** `sales@botlane.io` is the single public address. Every
CTA, the footer, `/privacy` and `/terms` now use it; `admin@botlane.io` no
longer appears anywhere on the site.

---

### 2026-08-13 — Payment terms: net 14, pause not penalise

Invoices are due **14 days** from issue. If one goes **14 days past due**,
sending pauses and resumes when settled. **No late fees, no interest.**

**Why net 14 rather than on receipt:** the client is a services firm being asked
to pay before results exist. On-receipt terms read as distrust at exactly the
moment trust is being established, and two weeks costs nothing at four clients.

**Why pausing rather than penalising:** the leverage is already total — the work
simply stops, and stopping is visible within days. A late fee on top adds an
adversarial clause to a page whose selling point is the absence of them, in
exchange for a few hundred dollars that will never be collected anyway. An
unpaid invoice from a firm this size usually signals a problem a conversation
resolves faster than a penalty.

**Rules out:** interest clauses, collection escalation, and auto-renew traps.

---

### 2026-08-13 — Hero form replaced with a mailto button (stopgap)

The hero's inline email capture was **proven to transmit nothing** and has been
removed. A standard Button linking to `mailto:sales@botlane.io` sits in its place.

**Evidence.** The submit event fires correctly — confirmed via both
`button.click()` and `form.requestSubmit()`. The button is a real `type="submit"`
inside the form, enabled, with nothing overlaying it, and the email input
validates. Yet **no outbound request is ever made**: no POST, fetch, XHR or
beacon, measured at browser network level rather than through page scripts.

Reproduced on the staging domain *and* on `botlane.io`, **after** a Google Sheet
and an email destination were connected, on a build whose `deploymentTime`
confirmed the connections were included. Domain restriction, stale build, click
interception and validation blocking are all ruled out.

**Therefore:** the fault is on Framer's side, not in the page. Likely causes are
plan-tier gating of form submissions, an incomplete Google OAuth leaving the
connection configured but unprovisioned, or the connection bound to a different
form object.

**Why swap rather than wait:** the site was already live. A silent form captures
nobody *and tells the visitor it worked*, so every person who filled it in was
lost without either party knowing. A mailto loses visitors with no mail client
configured, which is a smaller and visible failure.

**This is temporary.** Inline capture converts materially better on a hero. A
reminder is scheduled for 2026-08-15 to chase Framer support and restore the
form once a destination is confirmed working; restoring takes about two minutes.

---

### 2026-08-13 — Marketplace: a self-serve layer, built in the Framer project

> **Superseded 2026-08-14** — replaced by the single-page build in the
> 2026-08-14 entry.
>
> ~~this build was deleted and never shipped. The eight pages and seven
> placeholder products described below no longer exist.~~ **Wrong — corrected
> 2026-08-16.** Only the code file was deleted. **All seven
> `/marketplace/<slug>` pages are still live, publicly reachable and listed in
> `sitemap.xml`.** See the 2026-08-16 entry.
>
> The entry is kept because the three Framer constraints it records were learned
> the hard way and still apply. See the 2026-08-14 entry for what shipped.

A **Marketplace** of ready-to-deploy automations now exists at `/marketplace`,
with seven product pages under `/marketplace/<slug>`. It sits *below* the
managed service in the hierarchy and does not touch the homepage, the pricing,
or the ICP.

**Why it exists:** a consultancy that isn't ready for $5,000/month has no way to
buy anything today. The Marketplace gives them a $29–$349 entry point, and the
custom-automation CTA is the bridge from there back to implementation work.

**Where it lives:** the Framer project, per the "site is built in Framer"
decision above. Nothing lands in this repo.

**Data architecture.** All catalogue content — seven automations, three bundles,
seven categories, the pricing bands — lives in a typed DATA block at the top of
`MarketplaceUI.tsx`. No product copy is in page markup. Adding a product is one
entry plus a thin page holding one component instance bound to its slug.

**Two Framer constraints found the hard way, both worth knowing before the next
change:**

1. **Code files cannot import each other.** A relative import (`./Foo`) does not
   resolve, and the failure is silent in the worst way: the importing file then
   registers *zero* component exports, so every instance on the canvas renders
   nothing rather than showing an error. Data and UI therefore share one file.
2. **Instances bind to a code file, not to a named export within it.** An
   `insertUrl` with a `#NamedExport` fragment silently drops the fragment. The
   component is therefore a single default export with a `Section` control
   (featured / catalogue / bundles / card / detail / flow) instead of six
   separate exports.

**Nothing is marked BotLane Verified.** No workflow has been built, so every
entry is `verified: false` and the badge renders as "Preview"; the hero carries
a "catalogue in preview" note. The Verified UI, version and last-tested fields
are built and appear automatically when the flag is set. Do not set it early.

**No checkout.** Framer has no payment layer here and none was faked. Every buy
action opens a mail to `sales@botlane.io` pre-filled with the product, with a
line under the button stating checkout is not connected. Workflow files are not
exposed anywhere on the site.

**Rules out for now:** a Marketplace subscription, seller accounts, and any
public download of workflow files.

**A third MCP constraint, worth knowing before any future component edit.**
The plugin reads and writes only inside the **currently focused component** —
the one open in the Framer editor. Nodes in any other component report "not
found" on read, and edits targeting them return "No changes were made" rather
than an error, so a failed write looks identical to a no-op. `zoomIntoView`
pans the canvas but does **not** change focus; the component has to be opened
in the editor. `getProjectXml` reports which one is focused, and that is the
fastest way to diagnose a silent write.

Two further shape requirements for adding a node: target the **parent of the
insertion point** (not the insertion point itself) and list its existing
children by their original tag names, otherwise the call no-ops.

**Nav links are in.** `Marketplace` sits after `Pricing` in the NavBar and
after `FAQ` in the Footer's navigation column, both linking to `/marketplace`
and both using the text style their siblings use.

**Open:**
- Per-page SEO (title, description, OG) is unset. This is not a Marketplace
  problem — `/privacy` already serves the homepage's title and description.
- **The `Final CTA` button on `/` and `/privacy` points at
  `https://framer.link/6qZJXsm`**, not the mailto every other CTA uses. The last
  call to action on the page currently sends visitors off the site. Predates
  this work; flagged here because it is losing traffic now.

---

### 2026-08-14 — Marketplace ships as one page with an empty catalogue

`/marketplace` is a single page that sells the **model and the standard**, not a
catalogue. There are no products listed on it, no bundles UI and no checkout.

> **Corrected 2026-08-16.** This entry originally read "no product pages." That
> was never true of the deployed site: the seven `/marketplace/<slug>` pages
> from the superseded build were **not** deleted and remain live and indexable.
> The intent below stands; the statement of fact did not. See the 2026-08-16
> entry.

**Why nothing is listed.** No workflow has been built, tested or documented. The
previous attempt filled the page with seven invented placeholder products, which
meant the most prominent thing on a page about BotLane's quality standard was
seven things that did not exist. An empty catalogue that says so is worth more
than a full one that is fiction.

**What carries the page instead.** Two sections do the work a product grid
normally does:

- *What deploying one looks like* — the six-step flow from download to activate.
- *The workflow, and everything needed to run it* — the nine included items,
  followed by the three BotLane Verified claims rendered as **open circles**: a
  standard stated, not a standard met. An automation is listed only once all
  three are true.

The seven categories are shown with live counts driven off `AUTOMATIONS`; while
that array is empty each reads "soon" rather than "0".

**Buy action: none.** Two CTAs, both `mailto` — *Tell me when it opens* and
*Build my automation* — because the site's form backend is proven to transmit
nothing (see the hero-form entry above) and because there is nothing to sell
yet. No fake checkout, and no workflow files exposed anywhere.

**Architecture.** One Framer code file, `Marketplace.tsx`, one default export
with a `Section` control (`flow` / `included` / `categories`). A `DATA` block
holds the types, seven categories, six price bands, the nine included items, the
six setup steps and an empty `AUTOMATIONS`. Adding the first real product is one
entry there — the counts and states react on their own. Cards, grids, bundles
and detail renderers are deliberately unbuilt until there is a product for them.

**Rules out for now:** a Marketplace subscription, seller accounts, public
download of workflow files, and any use of the Verified mark.

**Open:**
- Mobile is unverified. The browser tooling available could not resize its
  viewport, so the page has never been seen below 1200px. `/marketplace` uses
  the same breakpoint classes as `/privacy`, so it should behave identically —
  but that is inference, not observation. **Look at it on a phone.**
- Per-page SEO is still unset across the whole site, not just here: `/privacy`
  serves the homepage's title and meta description.
- ~~**The `Final CTA` button on every page points at `https://framer.link/6qZJXsm`**~~
  — **fixed 2026-08-14.** `qa2d0SHwc` on node `eR_gxxu6m` now carries the same
  mailto as the hero and nav CTAs, byte-identical. Verified on `/`, `/privacy`,
  `/terms` and `/marketplace`; `framer.link` appears nowhere on the site.

  **What it taught us:** that button lives in a **shared layout frame**
  (`j8u8AHMod`) holding `SmoothScroll`, `NavBar`, `Noise`, `Final CTA` and
  `Footer` — and *nothing else*. Every page draws its chrome from it, which is
  why no page's own XML ever lists a nav or footer, and why one edit fixed all
  four pages at once. This is also the direct cause of the previous
  Marketplace build's duplicated chrome. **For any sitewide chrome change, edit
  that frame, once.** It is not reachable by traversal from a page; select the
  element on the Framer canvas and read it with `getSelectedNodesXml`.

**Deleting a page silently strips every link that pointed at it.** Framer stores
a link as a *page reference*, not a path. When the first Marketplace build was
deleted, the `link` attribute vanished outright from both the NavBar and Footer
`Marketplace` items — no error, no broken-link warning — and each rendered as
`href="./"`, which from any page resolves to `/`. So both nav entries quietly
pointed at the homepage while still reading "Marketplace". Re-setting
`link="/marketplace"` on each restored them. **After deleting any page, re-check
every link that referenced it**; the rendered `href` is the only reliable test,
because the page XML simply shows the attribute missing rather than wrong.

**Framer MCP constraint learned this round**, in addition to the three recorded
in the superseded entry: the plugin reads and writes **only inside the currently
focused page or component**. Elsewhere reads report "not found" and writes
return "No changes were made" rather than erroring, so a failed write is
indistinguishable from a no-op. `zoomIntoView` does not change focus;
`createPage` focuses what it creates; `getProjectXml` reports the current focus.
Also: `getNodeXml` does **not** reliably list a page's chrome — it omitted the
nav, footer and Final CTA on `/`, which is what caused the previous build to add
duplicates. Judge pages by rendered HTML, never by page XML.

---

### 2026-08-16 — Typography: Inter carries prose, mono carries labels and metadata

The intended split — Inter for body copy and UI detail, monospace for headlines,
section labels, buttons and signal-style metadata — is now explicit in the text
styles.

**Most of it was already true.** `/Body/Body`, `Small`, `Large`, `/Table/Cell`
and `/Table/Accent` were already Inter; headings were already Geist Mono. The
audit found only **one** style genuinely misassigned: `/Body/Body Mono` — 16px
JetBrains Mono with `tag="p"`, a paragraph style set in monospace. It is now
`GF;Inter-regular`, and its `-0.04em` tracking was removed (that tightening only
made sense as compensation for monospace advance widths).

**Two styles were deliberately left in monospace**, against the initial plan,
because inspecting their actual usage on `/` showed they carry labels rather
than prose:

| Style | Usage found | Verdict |
|---|---|---|
| `/Pricing/Alt` | "/ month", "or $13,500 / quarter", one sentence | 2 of 3 are price metadata — keep mono |
| `/Body/Small Mono` | "FOR DEVOPS CONSULTANCIES", "WHAT ARRIVES IN YOUR INBOX", 3 ✓ glyphs, one line of fine print | 5 of 6 are section labels — keep mono |

Switching either would have de-monoed the pricing units and section eyebrows —
the exact elements the split exists to preserve.

**The larger win was leading, not typeface.** Every body style was set at
`1.2em`–`1.3em`, which is headline leading applied to paragraphs; Inter cannot
read as scannable at that density. Now:

| Style | Was | Now |
|---|---|---|
| `/Body/Body` (16px) | 1.2em | 1.6em |
| `/Body/Body Mono` (16px) | 1.2em | 1.6em |
| `/Body/Small` (14px) | 1.3em | 1.55em |
| `/Body/Body Strong` (16px) | 1.2em | 1.5em |
| `/Body/Small Strong` (14px) | 1.3em | 1.5em |
| `/Body/Large` (20px) | 1.2em | 1.4em |

Larger sizes take tighter leading, hence the ramp. Headings (`1.1em`) and
`/Table/Cell` (already `1.5em`) were left alone.

**Deferred — Inter is loading from four sources.** `/Body/Body` reports
`font="Inter"`, `/Body/Small Strong` `"Inter-Medium"`, `/Table/Cell`
`"GF;Inter-regular"`, `/Table/Accent` `"GF;Inter-500"`, `/Body/Large`
`"FR;InterDisplay-Medium"`. Different providers of the same family can ship
different versions with different metrics, and it is extra font payload. Note
that the bare `"Inter"` selector **is not writable** — `manageTextStyle` rejects
it with "Font with selector Inter not found", so those styles predate the
current font picker and can only be normalized by rewriting them to `GF;` or
`FR;` selectors. `/Body/Large` using Inter *Display* is correct and should stay:
it is the right optical size at 20px.

**Two stray nodes still set prose in mono** and were left alone rather than
given new styles: "No autoresponder. No list resale. No obligation."
(`/Body/Small Mono`) and "Four client slots, then I stop taking work."
(`/Pricing/Alt`). Fixing them means a new prose-at-small style plus rebinding
two nodes, which is not worth it until someone judges them on the rendered page.

**`/Body/Body Mono` is now identical to `/Body/Body`.** It was kept as a
separate style only because rebinding its nodes requires visiting each page. It
is a merge candidate, and its name is now actively misleading.

**Verification limit — this was audited on `/` only.** `getNodeXml` on
`/privacy` returned "Node is not a text node"; reads work only on the currently
focused page, confirming the MCP focus constraint recorded above. `manageTextStyle`
is project-level so the changes propagate regardless, but their effect on
`/privacy`, `/terms` and `/marketplace` is **unobserved**. Look at those pages.

---

### 2026-08-16 — Correction: the seven Marketplace product pages were never deleted

**Status: live and indexable. Not a decision — a correction of the record.**

The 2026-08-13 and 2026-08-14 entries both state that the previous Marketplace
build's pages were deleted. They were not. Both entries have been annotated in
place rather than silently edited.

**What is actually deployed** (verified against `botlane.io` on 2026-08-16 by
fetching each URL, not by reading Framer page XML):

| URL | Status | Notes |
|---|---|---|
| `/marketplace` | 200 | The 2026-08-14 single-page build. Own title, h1 "Automations you don't need to build twice." Correct. |
| `/marketplace/lead-response-engine` | 200 | ~219KB, own title and h1. Reads as a real product. |
| `/marketplace/executive-brief-engine` | 200 | ~219KB, h1 present, title falls back to the homepage's. |
| 5 further `/marketplace/<slug>` pages | 200 | content-repurposing, client-onboarding, client-check-in, invoice-follow-up, meeting-to-action. All fully rendered. |

**They are being advertised to search engines**, which is worse than merely
existing:

- All seven appear in **`sitemap.xml`**
- `robots.txt` is `User-agent: * / Allow: /` and points at that sitemap
- None carries `noindex`

By contrast the genuine 404 path behaves correctly: an unknown URL returns the
404 page **with** `noindex`. The seven placeholder pages do not get that
treatment.

**What was actually deleted** was the old code file. `MarketplaceUI.tsx` is
gone and `Marketplace.tsx` (the single-page build) is in its place. The page
objects were left behind. This is the likely shape of the error: deleting the
code file was mistaken for deleting the build.

**Why this matters beyond tidiness.** The 2026-08-14 decision's stated reasoning
was that seven invented products on a page about BotLane's quality standard were
worth less than an empty catalogue that admits it. That reasoning is currently
inverted in production: `/marketplace` tells a visitor the catalogue is in
preview, while seven fictional products sit one search result away, with h1s,
looking purchasable. Nothing on them can be bought.

**Not yet decided — options, in preference order:**

1. **Delete the seven pages.** Matches the 2026-08-14 decision. **Then re-verify
   the `Marketplace` links in the NavBar and Footer by rendered `href`** — per
   the 2026-08-14 entry, deleting a page silently strips links pointing at it,
   which is exactly how those two links previously came to resolve to `/`.
2. **Keep them and make them invisible** — `noindex` plus removal from the
   sitemap. Correct if these products are actually coming.
3. **Leave as-is.** Only defensible if the products ship soon.

**Method note, and the reason this went unnoticed for two days.** Framer page
XML is not evidence about the deployed site, and `getNodeXml` reads only the
currently focused page — `/privacy` returned "Node is not a text node" simply
for not being focused. The 2026-08-14 entry already warned "judge pages by
rendered HTML, never by page XML"; this correction exists because that warning
was not applied to the deletion itself. **Fetching the URL is the only check
that counts.**

---

### 2026-08-16 — Two products, two prices: the service is $4,999 + $2,499/mo, the marketplace is $29–$399

BotLane sells **one service** and, separately, **individual automations**. Their
prices had merged, and the service price itself changed. Both are settled here.

**The service.** A **$4,999 one-time setup fee**, then **$2,499/month** to
maintain the system. Or **$11,246** for setup plus the first quarter prepaid, a
10% saving. This replaces the flat $5,000/month retainer decided 2026-08-13 and
the $13,500/quarter prepay decided the same day.

**Why the split.** The setup fee buys what takes real work to stand up — the
sending domain, its authentication and warm-up, the signal tracking, the ICP and
the sequences. The monthly is what it costs to operate that. A client who stops
paying keeps a system that was built; they stop having it run.

**Why $11,246 and not $13,500.** The old quarterly was 10% off three months at
$5,000. Carried across unchanged it would have been a **premium sold as a
discount**:

| | |
|---|---|
| Three months maintenance | $7,497 |
| Setup + three months | $12,496 |
| Old quarterly figure | **$13,500** |

$13,500 exceeded even setup plus a full quarter. $11,246 is $12,496 × 0.9, so
"Save 10%" stays literally true. The quarterly option survives because the
argument for it never depended on the number: a sending domain takes weeks to
warm, so a client judging on thirty days is judging warm-up, not results.

**Revenue shape changed, and not only upward.** Four clients now means roughly
$10k/month recurring where a flat retainer meant $20k, with the difference paid
up front. That makes cost-to-serve matter more, not less — an argument for the
shared pipeline in `vision.md`, not against it.

---

**The marketplace is a different product.** `/marketplace` automations are
priced **one-time, per product, $29–$399** by `PRICE_BANDS`. The service's
`INITIAL_MONTH_PRICE` / `MAINTENANCE_MONTHLY_PRICE` constants had leaked into
`Marketplace.tsx` and were rendering **$4,999 initial · $2,499/mo on all seven
listings** — pricing a downloadable workflow like a done-for-you engagement, and
making the "entry point for firms not ready for the retainer" cost more than the
retainer.

Products now carry their own `price`, set at their band ceiling: $79 (Client
Check-In, Invoice Follow-Up), $149 (Lead Response, Content Repurposing, Client
Onboarding, Meeting-to-Action), $399 (Executive Brief). A `priceExceedsBand()`
guard makes a price above its ceiling detectable. `CLAUDE.md` §1 now states the
separation explicitly, because this leak has happened once already.

**Also on the marketplace, same change:** "In development" badges are gone and
every listing carries a **Buy now** button with a cart icon. Because nothing has
actually been built, the listings now say **built to order** — scope and lead
time confirmed by email before payment, no instant checkout — and the file's
HONESTY RULES were updated to require that wording. Removing it turns a
build-to-order listing into a stock claim. The BotLane Verified mark still
renders only when `status` is `verified`.

---

**Where it landed:**

| Surface | State |
|---|---|
| `Marketplace.tsx` | Pushed, typechecks clean, verified byte-identical |
| Homepage pricing card + comparison table | 7 text nodes updated |
| `/terms` §4, §5, and the "last updated" date | Updated |
| `vision.md`, `CLAUDE.md` | Updated |

**Judgement calls in `/terms`, all reversible:**

- The setup fee is **not refunded once setup work has begun**, and refunded in
  full before it. The page already used that reasoning for prepaid quarters
  ("bought and warmed up front"); it belongs to the setup fee now.
- **Maintenance billing starts when sending starts**, not when setup is paid.
  Charging to maintain something not yet sending would contradict the site's own
  "honest window" argument.
- `"There is no setup fee"` was deleted from §4. `"No per-seat charge and no
  minimum term"` and `"cancel anytime"` survive — all still true, and all doing
  work against the agency comparison.

**Open:**

- **Nothing is published.** All Framer changes are project state until published.
- **The pricing card layout is unverified.** Its supporting line went from 7
  characters (`/ month`) to 23 in a non-wrapping horizontal stack inside a
  340–460px card. Both lines were shortened to reduce the risk, but the card has
  not been seen rendered. **Look at it at desktop and mobile width.**
- **`/terms` §11 caps liability at "fees paid in the three months before the
  claim arose."** With a large one-off setup fee it is now unclear whether that
  fee counts toward the cap. It did not matter under a flat retainer.
- Whether the quarterly prepay is available at signup only, or to an existing
  monthly client. The wording does not decide it.
- §12 governing law is still `[PROPOSED, NOT CONFIRMED]`.

---

### 2026-08-16 — Marketplace takes card payments: live Stripe catalogue, Buy now wired

The Marketplace now charges a card. Seven products, seven prices and seven
Payment Links exist in Stripe, and `Marketplace.tsx` points Buy now at them.

**These links are live and payable right now**, independent of the site. They
work for anyone holding the URL whether or not Framer has been published.

**Account:** `acct_1S1xniI9ZXWhlDED` ("Botlane"). Created 2026-08-16.

| Product | Price | Product ID | Price ID | Payment Link |
|---|---|---|---|---|
| Client Check-In Engine | $79 | `prod_V5BQzvbuNEJm5X` | `price_1U513TI9ZXWhlDEDlW5FE1kE` | `plink_1U5177I9ZXWhlDEDwuZZCpwH` |
| Invoice Follow-Up Engine | $79 | `prod_V5BQ8yqzidD9p5` | `price_1U513ZI9ZXWhlDEDqldk9Khi` | `plink_1U517FI9ZXWhlDEDP2jbP61f` |
| Lead Response Engine | $149 | `prod_V5BPOVa2oNWPAV` | `price_1U5136I9ZXWhlDEDV5XpwuUT` | `plink_1U516eI9ZXWhlDED2i3fmhgu` |
| Content Repurposing Engine | $149 | `prod_V5BQunDCLWfT8Y` | `price_1U513II9ZXWhlDEDFseit5kZ` | `plink_1U516rI9ZXWhlDEDNOizR7eY` |
| Client Onboarding Engine | $149 | `prod_V5BQyjt43WQwAY` | `price_1U513NI9ZXWhlDEDmhCZbWQs` | `plink_1U516zI9ZXWhlDED3Yu9O24Q` |
| Meeting-to-Action Engine | $149 | `prod_V5BQ7afwdQmfYw` | `price_1U513fI9ZXWhlDEDPLuPpcY0` | `plink_1U517OI9ZXWhlDEDKuZD2V7I` |
| Executive Brief Engine | $399 | `prod_V5BQjoJPdNY1w1` | `price_1U513lI9ZXWhlDEDPivDBCae` | `plink_1U517XI9ZXWhlDEDeY9zFdqK` |

Checkout URLs are the `buy.stripe.com/...` links in each product's `checkoutUrl`
in `Marketplace.tsx`. Every product carries `metadata.slug` matching the site, so
a Stripe payment can always be traced back to a listing.

**Three facts about the Stripe setup that are not obvious and cost time to
rediscover:**

1. **Test mode is not reachable through the connector.** It exposes exactly one
   context, and it is `livemode: true`. A read against `livemode: false` fails.
   There is no way to rehearse a change here — anything created is real. If a
   sandbox is ever needed, it has to be driven outside this connector.
2. **The links are card-only, and had to be.** The first creation attempt failed
   with *"No valid payment method types for this payment link"*: dynamic payment
   methods are not configured for USD on the account. Passing
   `payment_method_types: ["card"]` explicitly succeeded. This means Link, Cash
   App and everything else are currently turned away. Enabling payment methods in
   the dashboard and recreating the links without the restriction is a real
   improvement, not housekeeping.
3. **`customer_creation: "always"`** is set on every link, so each buyer becomes
   a Customer record. Fulfilment is a conversation, not a download; without this
   there would be a payment and no reliable way to contact the payer.

**The pre-order problem, and how it is handled.** Nothing in the catalogue has
been built, tested or documented — `status` is `in-development` on all seven.
A Buy now button that charges a card for that is a pre-order, and an undisclosed
pre-order is how chargebacks start. The disclosure now lives in **three places
that must agree**:

- the listing ("Built to order. Payment is taken now and the automation is built
  afterwards… refunded in full on request at any point before delivery"),
- the Stripe checkout page (`custom_text.submit`, plus a post-purchase
  confirmation explaining the build queue and refund path),
- `/terms` §5.

`HONESTY RULES` rule 5 in `Marketplace.tsx` now says so explicitly, because the
failure mode is someone tidying one of the three and not the others.

**Code shape.** `checkoutUrl` is optional on `Automation`, and `buyLink(a)`
returns `a.checkoutUrl ?? enquiryLink(a)`. A product without a link falls back to
an email enquiry rather than rendering a dead button, so links can be added one
at a time. Links were matched to products **by slug, not by array position** —
reordering `AUTOMATIONS` cannot silently mis-price a button.

**`/terms` updated to match**, since it previously said nothing about a one-off
card purchase: §4 now states marketplace automations are separate, $29–$399,
charged once and paid by card at checkout rather than invoiced; §5 carries the
refund policy — full refund on request before delivery, case by case after, to
`sales@botlane.io`, returned to the original card.

**Rules out for now:** a Marketplace subscription, seller accounts, public
download of workflow files, and any use of the Verified mark.

**Open:**

- **Nothing is published.** All Framer work — marketplace code, homepage
  pricing, `/terms` — is project state. The Stripe links are the exception and
  are already live.
- **Enable dynamic payment methods** and recreate the links without
  `payment_method_types`.
- **The first sale is a commitment to build that automation.** Seven live links
  means seven possible orders for things that do not exist. Either build the
  first product, or deactivate links for the ones that cannot be delivered
  quickly — a Payment Link can be set `active: false` without deleting it.
- The homepage pricing card layout is still unverified below desktop width.
- `/terms` §11 caps liability at "fees paid in the three months before the claim
  arose", which is now ambiguous for both the $4,999 setup fee and a one-off
  marketplace purchase.
- §12 governing law is still `[PROPOSED, NOT CONFIRMED]`.

---

### 2026-08-16 — Reversed: there is now a customer account area, invite-only

The 2026-08-12 entry ruled out client-facing surface, and `/terms` §2 told
customers there is "no login, no dashboard." **That is reversed.** A read-only
customer account area is now in scope, and the record is corrected rather than
left to contradict what gets built.

**What changed to justify it.** The Marketplace made this a two-product company.
Marketplace buyers can pay today and there is **no mechanism to deliver anything
to them** — no file, no documentation, no order history. That is a live defect,
not a hypothetical. Four service clients could always be served by email; an
unbounded number of Marketplace buyers cannot.

**Invite-only, and that is the whole point.** There is no public signup. Access
is granted by the operator:

- **Marketplace buyers — automatic.** A Stripe webhook on
  `checkout.session.completed` invites the email Stripe captured at checkout.
  (`customer_creation: "always"` is already set on every payment link, so the
  email is always there.)
- **Service clients — by hand.** There will be at most four, ever. Automating
  that would be building a feature for a spreadsheet-sized problem.

This preserves what the original decision was actually protecting. That rule was
never "customers must not see a screen" — it was **do not build self-serve
product surface**: no signup funnel, no onboarding, no configuration, nothing to
learn. An invite-only read-only account area is a deliverable, like the weekly
report. `vision.md` is amended in both places it made the claim.

**No passwords.** Access is **Google OAuth or a magic link**, gated on an
allowlist. Nothing is emailed to a customer that functions as a credential.
Sending passwords by email puts a permanent secret in two mailboxes, makes
resets and rotation the operator's problem, and turns a compromised mailbox into
a compromised account. Magic link is primary and Google is the convenience
option, because Google Workspace is common at these firms but not universal and
access must not depend on a customer's email provider.

**Rules out:** public signup, self-serve plan changes, any settings screen, and
any customer-editable state. The account area is **read-only**. If a customer
needs something changed, they email — that is the product.

---

### 2026-08-16 — Service billing moves into Stripe, still invoiced at net 14

The $4,999 setup and $2,499/month maintenance are now Stripe products, so the
account area has a real source for payments and next-due dates. Previously they
existed only as manual invoices and were queryable from nowhere.

| Product | Price | Product ID | Price ID |
|---|---|---|---|
| Outbound Infrastructure — Setup | $4,999 one-time | `prod_V5Fz8abbkTn2MB` | `price_1U55TuI9ZXWhlDEDTyBslycE` |
| Outbound Infrastructure — Maintenance | $2,499/mo recurring | `prod_V5G0Ix2eqUPCDv` | `price_1U55U1I9ZXWhlDEDOB16iNTk` |
| Outbound Infrastructure — Setup + First Quarter | $11,246 one-time | `prod_V5G0SGwlipe3hO` | `price_1U55U8I9ZXWhlDEDeS379AjM` |

**No payment links on any of these, deliberately.** A $4,999 engagement is
invoiced to a named client after a conversation. Public buy URLs are for the
Marketplace; the service is not self-serve and must not look like it is.

**Stripe does not mean card-on-file.** Subscriptions are created with
`collection_method: send_invoice` and `days_until_due: 14`, so Stripe issues the
invoice and the client pays it. **`/terms` §4 therefore needs no change** — the
mechanism moved, the deal did not.

This is load-bearing. The 2026-08-13 payment-terms entry chose net 14 precisely
because "the client is a services firm being asked to pay before results exist,
and on-receipt terms read as distrust at exactly the moment trust is being
established." Auto-charging a card on the 1st would have discarded that
reasoning silently. All three products carry `metadata.billing = invoice-net-14`
so the intent travels on the object.

**Subscription start date:** the maintenance subscription is anchored to when
**sending begins**, not when the setup invoice is paid. Warm-up takes weeks, and
`/terms` §4 already says the first maintenance invoice is issued when sending
starts. Do not let Stripe default the billing anchor to the creation date.

---

### 2026-08-16 — Database is a new Supabase project in `us-east-1`

**Settles Q3**, open since 2026-08-12. New project **`BotLane`**
(`tqfyhgzaxaakaewmwamc`), region `us-east-1`, free tier at $0/month.

**A new project rather than restoring the old one.** `Solo's System`
(`fyofjbxukmovxvkdzuxf`) sits in `ap-northeast-1` (Tokyo), paused, and has never
held data. **Supabase cannot move a project between regions** — the only way to
change region is to create a new project. Doing that now costs nothing because
there is nothing to migrate. Doing it after the account area has customers in it
is a migration with downtime. The old project is abandoned, not restored.

**Why `us-east-1` and not somewhere closer to the operator.** The customers are
US and the account area is the thing they touch; the operator is in Bangalore and
touches admin tooling. Given the choice, put the latency on the person who can
wait. A customer bouncing off a slow dashboard is not recoverable; the operator
waiting 200ms on an admin query is not a cost.

Q3's original framing assumed the only workload was a batch pipeline, where
region barely matters. The account area changed that — it is interactive and
customer-facing, which is what makes the region a real decision rather than a
coin toss.

**Also closes R3** ("Supabase project is paused"), which no longer describes
anything. Both are removed from `open-questions.md` per that file's convention.

**Still open:** Q1 (ingestion approach) and Q2 (pipeline stack). Note this
decision does **not** settle Q2 — choosing Postgres-on-Supabase for the account
area does not choose the language or framework for the ingestion pipeline, and
should not be read as having done so.

---

### 2026-08-16 — Account area schema: read-only and isolated by the database

Applied to Supabase project `BotLane` (`tqfyhgzaxaakaewmwamc`). Three migrations,
now in `supabase/migrations/` — **the first application code in this repository.**

**Five tables.** `customers` (also the invite allowlist), `orders` (Marketplace
purchases), `engagements` (service clients), `payments`, `documents`.

**Three properties are enforced by Postgres, not by application code.** Each was
tested rather than assumed:

| Property | How | Verified |
|---|---|---|
| Tenant isolation | RLS on every table via `private.current_customer_id()` | Queried as customer A: saw own row, **0 rows of customer B** |
| Invite-only | Trigger on `auth.users` rejects any email not in `customers` | Insert refused: `42501 This email address is not on the BotLane account list` |
| Read-only | **No** insert/update/delete policy exists on any table | Insert as authenticated: `42501 new row violates row-level security policy` |

The read-only property is the interesting one. It is not a frontend convention —
there is simply no write policy for the `authenticated` role anywhere, so a
customer cannot write even if the app is wrong or hostile. All writes come from
the operator or the Stripe webhook using `service_role`, which bypasses RLS.

**Design decisions worth keeping:**

- **`payments` is a mirror of Stripe, not a ledger.** Stripe stays
  authoritative; the table exists so the dashboard does not make live Stripe
  calls on page load. If the two disagree, this table is wrong. Rendering a
  Stripe-hosted invoice URL rather than our own invoice keeps it that way.
- **Payment and fulfilment are separate columns on `orders`.** Everything is
  built to order, so an order is legitimately paid weeks before delivered.
  Collapsing them into one status would make that state unrepresentable.
- **`engagements.sending_started_at` is the maintenance billing anchor**, not
  the setup payment date. Warm-up takes weeks and `/terms` §4 says the first
  maintenance invoice is issued when sending begins. A `CHECK` keeps `ended`
  and `ended_at` consistent.
- **`customers.notes` is operator-only** and withheld by a column-level grant,
  not by hoping nobody selects it.
- **Status columns are `text` + `CHECK`, not enums.** This schema will change;
  adding a value to a `CHECK` is a one-line migration, `ALTER TYPE` is not.
- **`documents.storage_path` must start with the `customer_id`**, because the
  storage policy authorises on the first path segment. Break that convention and
  the bucket leaks.

**The linter caught something worth recording.** Both `SECURITY DEFINER`
functions were originally in `public`, which PostgREST exposes — meaning they
were callable over HTTP at `/rest/v1/rpc/`. They were moved to a `private`
schema, which PostgREST does not expose, so they remain usable from policies and
triggers with no HTTP surface. Security advisors now return **zero** findings.
**Run `get_advisors` after every schema change**; this was not obvious from the
code.

**Open:**

- **No `updated_at` protection against clock skew** and no soft-delete anywhere.
  Deliberate for now; revisit if data ever needs auditing.
- The app itself does not exist. Stack is still undecided (`CLAUDE.md` §3), and
  that is the next decision — the schema deliberately does not assume one.
- The Stripe webhook that populates `orders`, `payments` and invites the buyer
  is not built.
- Google OAuth needs a Google Cloud project and consent screen configured under
  the operator's account. Supabase Auth needs the provider enabled. Neither is
  done, and neither should be done by an agent.
