"""Confirm first_published / publishedAt are universal, not one-board flukes.

Also find a working Lever board.
"""

import json
import ssl
import urllib.error
import urllib.request
from datetime import datetime, timezone

CTX = ssl.create_default_context()
UA = {"User-Agent": "BotLane-research/1.0 (evaluating public job board APIs)"}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=25, context=CTX) as r:
        return json.loads(r.read().decode())


def days(value):
    try:
        if isinstance(value, (int, float)):
            ts = value / 1000 if value > 1e11 else value
            dt = datetime.fromtimestamp(ts, tz=timezone.utc)
        else:
            dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return (datetime.now(timezone.utc) - dt).days
    except Exception:
        return None


print("GREENHOUSE — is first_published on every job, and how old do they get?")
print("-" * 72)
for tok in ["figma", "discord", "flexport", "robinhood", "airtable"]:
    try:
        jobs = get(f"https://boards-api.greenhouse.io/v1/boards/{tok}/jobs").get("jobs", [])
        if not jobs:
            print(f"  {tok:11} 0 jobs")
            continue
        have = sum(1 for j in jobs if j.get("first_published"))
        ages = sorted(d for d in (days(j.get("first_published")) for j in jobs) if d is not None)
        stale = [d for d in ages if d >= 60]
        print(f"  {tok:11} {len(jobs):4} jobs | first_published on {have}/{len(jobs)}"
              f" | oldest {ages[-1] if ages else '-'}d | {len(stale)} already 60d+")
    except urllib.error.HTTPError as e:
        print(f"  {tok:11} HTTP {e.code}")
    except Exception as e:
        print(f"  {tok:11} {type(e).__name__}")

print()
print("ASHBY — same question")
print("-" * 72)
for name in ["linear", "vanta", "deel", "mercury", "clickhouse"]:
    try:
        jobs = get(f"https://api.ashbyhq.com/posting-api/job-board/{name}").get("jobs", [])
        if not jobs:
            print(f"  {name:11} 0 jobs")
            continue
        have = sum(1 for j in jobs if j.get("publishedAt"))
        ages = sorted(d for d in (days(j.get("publishedAt")) for j in jobs) if d is not None)
        stale = [d for d in ages if d >= 60]
        print(f"  {name:11} {len(jobs):4} jobs | publishedAt on {have}/{len(jobs)}"
              f" | oldest {ages[-1] if ages else '-'}d | {len(stale)} already 60d+")
    except urllib.error.HTTPError as e:
        print(f"  {name:11} HTTP {e.code}")
    except Exception as e:
        print(f"  {name:11} {type(e).__name__}")

print()
print("LEVER — find any working board")
print("-" * 72)
for co in ["eventbrite", "kickstarter", "quora", "mixpanel", "box", "lever",
           "leverdemo", "spotify", "yelp", "cloudflare"]:
    try:
        d = get(f"https://api.lever.co/v0/postings/{co}?mode=json")
        if isinstance(d, list) and d:
            j = d[0]
            keys = [k for k in j if any(w in k.lower() for w in ("date", "created", "posted"))]
            print(f"  {co:11} {len(d):4} postings | date-ish keys: {keys}")
            for k in keys:
                print(f"              {k} = {j[k]} -> {days(j[k])} days old")
            break
        print(f"  {co:11} empty")
    except urllib.error.HTTPError as e:
        print(f"  {co:11} HTTP {e.code}")
    except Exception as e:
        print(f"  {co:11} {type(e).__name__}")
