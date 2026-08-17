"""Probe the three ATS APIs for posting dates.

open-questions.md: does a posting expose an ORIGINAL date? If yes, "open 60+
days" is computable on day one. If no, it needs accumulated observation and the
first sample is two months away.

Read-only public endpoints, a handful of requests, no keys.
"""

import json
import ssl
import urllib.error
import urllib.request
from datetime import datetime, timezone

CTX = ssl.create_default_context()
UA = {"User-Agent": "BotLane-research/1.0 (evaluating public job board APIs)"}

GREENHOUSE = ["stripe", "figma", "discord", "robinhood", "flexport"]
LEVER = ["netflix", "plaid", "brex", "ramp"]
ASHBY = ["ramp", "linear", "vanta", "deel"]


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=25, context=CTX) as r:
        return json.loads(r.read().decode())


def age(value):
    """Turn whatever the field holds into days-old, or None."""
    try:
        if isinstance(value, (int, float)):
            ts = value / 1000 if value > 1e11 else value
            dt = datetime.fromtimestamp(ts, tz=timezone.utc)
        else:
            dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return round((datetime.now(timezone.utc) - dt).days)
    except Exception:
        return None


def date_fields(obj):
    return {
        k: v for k, v in obj.items()
        if any(w in k.lower() for w in ("date", "created", "updated", "published", "opened", "posted"))
    }


print("=" * 72)
print("GREENHOUSE   boards-api.greenhouse.io/v1/boards/{token}/jobs")
print("=" * 72)
for tok in GREENHOUSE:
    try:
        d = get(f"https://boards-api.greenhouse.io/v1/boards/{tok}/jobs?content=true")
        jobs = d.get("jobs", [])
        if not jobs:
            print(f"  {tok:12} 0 jobs")
            continue
        j = jobs[0]
        f = date_fields(j)
        print(f"  {tok:12} {len(jobs):4} jobs | date fields: {list(f)}")
        for k, v in f.items():
            print(f"               {k} = {v}  -> {age(v)} days old")
        break
    except urllib.error.HTTPError as e:
        print(f"  {tok:12} HTTP {e.code}")
    except Exception as e:
        print(f"  {tok:12} {type(e).__name__}: {str(e)[:60]}")

print()
print("=" * 72)
print("LEVER        api.lever.co/v0/postings/{company}?mode=json")
print("=" * 72)
for co in LEVER:
    try:
        d = get(f"https://api.lever.co/v0/postings/{co}?mode=json")
        if not isinstance(d, list) or not d:
            print(f"  {co:12} empty")
            continue
        j = d[0]
        f = date_fields(j)
        print(f"  {co:12} {len(d):4} postings | date fields: {list(f)}")
        for k, v in f.items():
            print(f"               {k} = {v}  -> {age(v)} days old")
        break
    except urllib.error.HTTPError as e:
        print(f"  {co:12} HTTP {e.code}")
    except Exception as e:
        print(f"  {co:12} {type(e).__name__}: {str(e)[:60]}")

print()
print("=" * 72)
print("ASHBY        api.ashbyhq.com/posting-api/job-board/{name}")
print("=" * 72)
for name in ASHBY:
    try:
        d = get(f"https://api.ashbyhq.com/posting-api/job-board/{name}")
        jobs = d.get("jobs", [])
        if not jobs:
            print(f"  {name:12} 0 jobs")
            continue
        j = jobs[0]
        f = date_fields(j)
        print(f"  {name:12} {len(jobs):4} jobs | date fields: {list(f)}")
        for k, v in f.items():
            print(f"               {k} = {v}  -> {age(v)} days old")
        break
    except urllib.error.HTTPError as e:
        print(f"  {name:12} HTTP {e.code}")
    except Exception as e:
        print(f"  {name:12} {type(e).__name__}: {str(e)[:60]}")
