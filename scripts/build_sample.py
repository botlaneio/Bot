"""Rebuild the sample, filtered to companies a consultancy could actually sell to.

SIZE PROXY: total open roles on the company's own board.

No headcount field exists in either ATS, and Apollo credits are scarce (200 lead
credits, ~5 samples) so they are not spent here. Board size is free and
correlates well enough: Stripe 577 open roles, Figma 161, Pylon a handful.

It is a proxy, not truth. A 60-person company hiring hard can post 40 roles; a
2,000-person company in a freeze can post 20. So it is paired with an explicit
exclusion list of companies known to be far too large, which no threshold
catches reliably.
"""

import json
import re
import ssl
import sys
import time
import urllib.request
from datetime import datetime, timezone

CTX = ssl.create_default_context()
UA = {"User-Agent": "BotLane-research/1.0 (+https://botlane.io)"}
NOW = datetime.now(timezone.utc)

MAX_OPEN_ROLES = 120           # above this, assume an in-house platform team

# Public, or large enough that a 20-50 person consultancy is not a credible
# vendor. Board size alone does not always catch these.
TOO_BIG = {
    "stripe", "figma", "snowflake", "mongodb", "twilio", "okta", "databricks",
    "cloudflare", "datadog", "elastic", "gitlab", "confluent", "airbnb",
    "pinterest", "reddit", "lyft", "instacart", "doordash", "waymo", "nuro",
    "zoox", "peloton", "coursera", "grammarly", "duolingo", "asana", "notion",
    "monday", "hashicorp", "digitalocean", "fastly", "segment", "amplitude",
    "scaleai", "coreweave", "cerebras", "perplexity", "verkada", "samsara",
    "brex", "ramp", "rippling", "gusto", "plaid", "affirm", "chime", "carta",
    "webflow", "intercom", "front", "klaviyo", "fivetran", "clickup", "vercel",
    "netlify", "sentry", "auth0", "snyk", "wiz", "deel", "benchling", "oscar",
}

SLUG_SOURCES = ["forty_final.json"]

EXTRA = """
knot highnote pylon alloy knock material speakeasy propel eightsleep
lithic increase column moov dwolla astra orum stedi
persona middesk sardine unit21 socure inscribe taktile greenlite
census hightouch polytomic estuary prefect dagster
tinybird materialize turso xata neon edgedb questdb
baseten modal replicate together fal predibase octoml
anyscale outerbounds union metaflow
temporal inngest trigger defer hatchet windmill mergent
courier novu resend loops
workos clerk stytch descope frontegg propelauth kinde
doppler infisical akeyless entro
teleport pomerium boundary
vanta drata secureframe
spacelift env0 dagger depot namespace blacksmith
porter northflank qovery koyeb render
mezmo cribl edgedelta groundcover last9 signoz
rootly firehydrant blameless incident jeli
statsig launchdarkly split flagsmith
kubecost vantage cloudzero finout
retool appsmith budibase pipedream tray
gem ashby workable
pave assemble
plain devrev pylon
mux cloudinary imgix bytescale
sanity storyblok prismic contentful
mintlify readme gitbook scalar stainless
merge nango finch truv pinwheel argyle knot
greptile sourcery codeium
lightdash omni metabase
runway pigment causal abacum
"""


def get(url, timeout=18):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
        return json.loads(r.read().decode())


def days_since(v):
    try:
        if isinstance(v, (int, float)):
            ts = v / 1000 if v > 1e11 else v
            dt = datetime.fromtimestamp(ts, tz=timezone.utc)
        else:
            dt = datetime.fromisoformat(str(v).replace("Z", "+00:00"))
        return (NOW - dt).days
    except Exception:
        return None


INFRA = re.compile(
    r"(\bsre\b|site\s*reliability|"
    r"\b(infrastructure|platform|cloud|production|reliability)\s+"
    r"(engineer|engineering|architect|lead|manager|developer)|"
    r"\bdev\s*ops\b|\bkubernetes\b|\bplatform\s+(infrastructure|operations)\b|"
    r"\bcloud\s+(infrastructure|operations)\b)", re.I)
NOT_INFRA = re.compile(
    r"\b(it|people|hr|business|salesforce|netsuite|workday|revenue|sales|gtm|"
    r"go.to.market|enablement|marketing|finance|support|customer|bi|field|"
    r"partner|data\s*platform|ml\s*platform|machine\s*learning|analytics|"
    r"electrical|mechanical|hardware|manufacturing|quality|supply|structural|"
    r"thermal|avionics|propulsion|test\s*engineer|android|ios|mobile)\b", re.I)
NON_US = re.compile(
    r"\b(europe|emea|apac|latam|london|berlin|paris|amsterdam|dublin|madrid|"
    r"barcelona|lisbon|munich|zurich|stockholm|copenhagen|oslo|warsaw|prague|"
    r"bangalore|bengaluru|hyderabad|pune|delhi|mumbai|chennai|gurgaon|noida|"
    r"singapore|tokyo|seoul|sydney|melbourne|auckland|toronto|vancouver|"
    r"montreal|ottawa|tel\s*aviv|dubai|sao\s*paulo|mexico\s*city|bogota|"
    r"buenos\s*aires|santiago|cairo|lagos|nairobi|united\s*kingdom|germany|"
    r"france|netherlands|ireland|spain|portugal|poland|romania|india|israel|"
    r"canada|australia|new\s*zealand|japan|korea|china|brazil|argentina|"
    r"colombia|chile|mexico|philippines|vietnam)\b", re.I)
US_HINT = re.compile(
    r"(united\s*states|\busa\b|\bu\.s\.|\bus\b|new\s*york|san\s*francisco|"
    r"seattle|austin|boston|chicago|denver|atlanta|los\s*angeles|san\s*diego|"
    r"portland|miami|dallas|houston|philadelphia|washington|nyc|bay\s*area|"
    r"palo\s*alto|mountain\s*view|sunnyvale|santa\s*clara|menlo\s*park|"
    r"redwood\s*city|oakland|brooklyn|bellevue|salt\s*lake|nashville|charlotte|"
    r"raleigh|durham|pittsburgh|detroit|minneapolis|phoenix|san\s*jose|boulder|"
    r"foster\s*city|livingston|san\s*mateo|"
    r",\s*(ca|ny|wa|tx|ma|il|co|ga|fl|or|pa|nc|va|md|nj|ut|az|mn|tn|oh|mi|wi)\b)",
    re.I)


def ok(t, loc):
    return bool(INFRA.search(t) and not NOT_INFRA.search(t) and loc
                and not NON_US.search(loc) and US_HINT.search(loc))


slugs = set(EXTRA.split())
for f in SLUG_SOURCES:
    try:
        slugs |= {r["company"] for r in json.load(open(f, encoding="utf-8"))["companies"]}
    except Exception:
        pass
slugs = sorted(s for s in slugs if s and s.isascii())

rows, skipped_big = [], []
sys.stderr.write(f"probing {len(slugs)} slugs, recording board size...\n")

for i, slug in enumerate(slugs):
    for kind in ("gh", "ashby"):
        try:
            if kind == "gh":
                jobs = get(f"https://boards-api.greenhouse.io/v1/boards/{slug}/jobs").get("jobs", [])
                getloc = lambda j: (j.get("location") or {}).get("name", "")
                getdate, geturl = (lambda j: j.get("first_published")), (lambda j: j.get("absolute_url", ""))
            else:
                jobs = get(f"https://api.ashbyhq.com/posting-api/job-board/{slug}").get("jobs", [])
                getloc = lambda j: j.get("location") or ""
                getdate, geturl = (lambda j: j.get("publishedAt")), (lambda j: j.get("jobUrl", ""))
            if not jobs:
                continue
            total = len(jobs)
            if slug in TOO_BIG or total > MAX_OPEN_ROLES:
                skipped_big.append((slug, total))
                continue
            for j in jobs:
                t, loc = j.get("title", ""), getloc(j)
                if ok(t, loc):
                    d = days_since(getdate(j))
                    if d and d >= 60:
                        rows.append({"company": slug, "ats": kind, "title": t, "location": loc,
                                     "days": d, "open_roles": total, "url": geturl(j)})
        except Exception:
            pass
    if (i + 1) % 40 == 0:
        sys.stderr.write(f"  {i+1}/{len(slugs)}  companies: {len({r['company'] for r in rows})}\n")
    time.sleep(0.03)

best = {}
for r in rows:
    if r["company"] not in best or r["days"] > best[r["company"]]["days"]:
        best[r["company"]] = r
ranked = sorted(best.values(), key=lambda r: -r["days"])

json.dump({"generated": NOW.isoformat(),
           "criteria": f"US infra role 60+ days open; company board <= {MAX_OPEN_ROLES} open roles; "
                       "known-large companies excluded",
           "size_proxy": "total open roles on the company's own ATS board",
           "company_count": len(ranked), "companies": ranked},
          open("sized_final.json", "w", encoding="utf-8"), indent=2)

sys.stderr.write(f"\nexcluded as too large: {len(set(s for s,_ in skipped_big))}\n")
sys.stderr.write(f"FINAL: {len(ranked)} companies\n\n")

print(f"{'#':>3} {'DAYS':>5} {'ROLES':>6}  {'COMPANY':<15} {'ROLE':<44} LOCATION")
print("-" * 118)
for n, r in enumerate(ranked[:40], 1):
    print(f"{n:>3} {r['days']:>5} {r['open_roles']:>6}  {r['company']:<15} "
          f"{r['title'][:44]:<44} {r['location'][:22]}")
print(f"\n{len(ranked)} companies qualified.")
