"""Fetch and normalise public ATS job boards.

Three providers, one shape. Everything here is deliberately dumb: it fetches,
it renames fields, and it reports honestly whether the fetch worked. It makes
no lifecycle decisions — no "this posting is gone", no "this one is new" —
because those are claims that end up in a customer's email, and they are
decided in one place, inside public.ingest_ats_board (see
supabase/migrations/20260818153940_pipeline_close_by_run_id.sql).

The one judgement this module DOES make is the difference between "the board
says there are no postings" and "we failed to ask". Getting that wrong
manufactures withdrawal signals, so failure is never silently normalised into
an empty list.

Endpoints are public and keyless, verified 2026-08-17 (scripts/ats_probe.py):

    greenhouse  boards-api.greenhouse.io/v1/boards/{token}/jobs   first_published
    ashby       api.ashbyhq.com/posting-api/job-board/{token}     publishedAt
    lever       api.lever.co/v0/postings/{token}?mode=json        createdAt (epoch ms)

stdlib only, on purpose: the repository has no dependency manifest and no build,
and a daily HTTP poll is not a good enough reason to introduce one.
"""

import json
import ssl
import urllib.error
import urllib.request
from datetime import datetime, timezone

SOURCES = ("greenhouse", "ashby", "lever")

CTX = ssl.create_default_context()
UA = {"User-Agent": "BotLane-ingest/1.0 (+https://botlane.io)"}
TIMEOUT = 25

BOARD_URL = {
    "greenhouse": "https://boards-api.greenhouse.io/v1/boards/{token}/jobs",
    "ashby": "https://api.ashbyhq.com/posting-api/job-board/{token}",
    "lever": "https://api.lever.co/v0/postings/{token}?mode=json",
}


class Fetch:
    """One attempt at one board.

    `status` mirrors pipeline.poll_runs.status and is the whole point of the
    class: `postings` being empty means nothing until you have read `status`.
    """

    __slots__ = ("source", "token", "status", "http_status", "error", "postings", "started_at")

    def __init__(self, source, token, status, http_status=None, error=None,
                 postings=None, started_at=None):
        self.source = source
        self.token = token
        self.status = status
        self.http_status = http_status
        self.error = error
        self.postings = postings or []
        self.started_at = started_at or _now_iso()

    @property
    def ok(self):
        return self.status == "ok"

    def payload(self, organization_slug=None, organization_name=None):
        """The jsonb argument for public.ingest_ats_board."""
        return {
            "source": self.source,
            "board_token": self.token,
            "organization_slug": organization_slug or self.token,
            "organization_name": organization_name,
            "board_url": BOARD_URL[self.source].format(token=self.token),
            "fetch_status": self.status,
            "http_status": self.http_status,
            "error": self.error,
            "started_at": self.started_at,
            "postings": self.postings,
        }

    def __repr__(self):
        return (f"<Fetch {self.source}/{self.token} {self.status} "
                f"{len(self.postings)} postings>")


def _now_iso():
    return datetime.now(timezone.utc).isoformat()


def _iso(value):
    """Whatever the provider calls a date, as an ISO 8601 string, or None.

    Lever hands back epoch milliseconds; Greenhouse and Ashby hand back
    strings, occasionally with a trailing Z that fromisoformat rejects on
    older Pythons. Anything unparseable becomes None rather than a guess: a
    wrong date is worse than a missing one, because the missing one is visible
    downstream as days_open_is_observed.
    """
    if value is None or value == "":
        return None
    try:
        if isinstance(value, (int, float)):
            seconds = value / 1000 if value > 1e11 else value
            return datetime.fromtimestamp(seconds, tz=timezone.utc).isoformat()
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.isoformat()
    except (ValueError, OSError, OverflowError):
        return None


def _get(url, timeout=TIMEOUT):
    request = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(request, timeout=timeout, context=CTX) as response:
        return json.loads(response.read().decode()), response.status


def _normalise_greenhouse(data):
    postings = []
    for job in data.get("jobs", []):
        job_id = job.get("id")
        title = job.get("title")
        if job_id is None or not title:
            continue
        postings.append({
            "posting_id": str(job_id),
            "title": title,
            "location": (job.get("location") or {}).get("name"),
            # Greenhouse's list endpoint carries no employment type at all.
            # Null here means "not published", never "full time".
            "employment_type": None,
            "url": job.get("absolute_url"),
            "first_published_at": _iso(job.get("first_published")),
        })
    return postings


def _normalise_ashby(data):
    postings = []
    for job in data.get("jobs", []):
        job_id = job.get("id")
        title = job.get("title")
        if job_id is None or not title:
            continue
        postings.append({
            "posting_id": str(job_id),
            "title": title,
            "location": job.get("location"),
            "employment_type": job.get("employmentType"),
            "url": job.get("jobUrl"),
            "first_published_at": _iso(job.get("publishedAt")),
        })
    return postings


def _normalise_lever(data):
    postings = []
    for job in data if isinstance(data, list) else []:
        job_id = job.get("id")
        title = job.get("text")
        if job_id is None or not title:
            continue
        categories = job.get("categories") or {}
        postings.append({
            "posting_id": str(job_id),
            "title": title,
            "location": categories.get("location"),
            "employment_type": categories.get("commitment"),
            "url": job.get("hostedUrl"),
            "first_published_at": _iso(job.get("createdAt")),
        })
    return postings


NORMALISE = {
    "greenhouse": _normalise_greenhouse,
    "ashby": _normalise_ashby,
    "lever": _normalise_lever,
}


def fetch_board(source, token, timeout=TIMEOUT):
    """Fetch one board. Never raises: every outcome is a Fetch with a status."""
    if source not in SOURCES:
        raise ValueError(f"unknown source {source!r}")

    started_at = _now_iso()
    url = BOARD_URL[source].format(token=token)

    try:
        data, http_status = _get(url, timeout=timeout)
    except urllib.error.HTTPError as exc:
        # Includes 404. A board that 404s today may simply have been renamed,
        # so this is a failed fetch and closes nothing — board_health surfaces
        # it by way of consecutive_failures.
        return Fetch(source, token, "http_error", http_status=exc.code,
                     error=f"HTTP {exc.code}", started_at=started_at)
    except (urllib.error.URLError, TimeoutError, ssl.SSLError, ConnectionError) as exc:
        return Fetch(source, token, "network_error",
                     error=f"{type(exc).__name__}: {exc}"[:500], started_at=started_at)
    except json.JSONDecodeError as exc:
        return Fetch(source, token, "parse_error",
                     error=f"invalid JSON: {exc}"[:500], started_at=started_at)

    try:
        postings = NORMALISE[source](data)
    except (AttributeError, TypeError) as exc:
        # The provider answered with a shape we do not recognise. Also not an
        # empty board.
        return Fetch(source, token, "parse_error", http_status=http_status,
                     error=f"unexpected shape: {type(exc).__name__}: {exc}"[:500],
                     started_at=started_at)

    # 'ok' with zero postings is left to the database to classify: only it
    # knows whether we are already holding open postings for this board, which
    # is what separates "genuinely empty" from "something is wrong".
    return Fetch(source, token, "ok", http_status=http_status,
                 postings=postings, started_at=started_at)


def discover_boards(slug, sources=SOURCES, timeout=TIMEOUT):
    """Probe a candidate slug against each ATS; return the fetches that hit.

    Board tokens are discovered exactly here and then stored, never derived
    again: Lever slugs in particular are not guessable — eventbrite,
    kickstarter, quora, mixpanel and box all 404'd on 2026-08-17.

    A board that answers with zero postings is still a real board, and is
    returned: registering it starts the clock, which is the point.
    """
    found = []
    for source in sources:
        fetch = fetch_board(source, slug, timeout=timeout)
        if fetch.ok:
            found.append(fetch)
    return found
