"""Talking to Supabase.

Two calls, both RPC, both service-role only:

    ingest_ats_board(payload)      -- hand over one board fetch
    pipeline_active_boards(limit)  -- ask what to poll

The pipeline tables themselves are not reachable over HTTP by design (the
schema is not exposed by PostgREST), so this module cannot accidentally grow
into a general data-access layer. Every write goes through the one function
that owns the lifecycle rules.

Credentials come from the environment and are never logged:

    SUPABASE_URL                https://<ref>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY   service_role key — bypasses RLS, secret

In GitHub Actions both are repository secrets. Locally, put them in
Bot/.env.local.txt, which .gitignore already covers via `.env.*`.
"""

import json
import os
import ssl
import time
import urllib.error
import urllib.request

CTX = ssl.create_default_context()
TIMEOUT = 60
RETRIES = 3

ENV_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        ".env.local.txt")


class ConfigError(RuntimeError):
    pass


def _load_env_file(path=ENV_FILE):
    """Read KEY=value lines from .env.local.txt without overriding real env vars.

    Convenience for running by hand on the dev box. CI sets real environment
    variables and never reaches this.
    """
    if not os.path.exists(path):
        return
    try:
        with open(path, encoding="utf-8-sig") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                if key and key not in os.environ:
                    os.environ[key] = value
    except OSError:
        pass


def credentials():
    _load_env_file()
    url = (os.environ.get("SUPABASE_URL") or "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or ""
    if not url or not key:
        raise ConfigError(
            "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set.\n"
            "  Local: add them to Bot/.env.local.txt (gitignored).\n"
            "  CI:    repository secrets of the same name.\n"
            "  The service_role key is at Supabase > Project Settings > API "
            "Keys, on the botlaneio account, project BotLane "
            "(nekribxexmpmpzefcpvn). It bypasses RLS: never print or commit it.")
    return url, key


def call_rpc(function_name, payload, timeout=TIMEOUT, retries=RETRIES):
    """POST to /rest/v1/rpc/<function_name>, with retries on transient failure.

    Retrying is safe because the ingest function is a single transaction: a
    call either committed or it did not, so a repeat cannot half-apply. A
    genuinely duplicated call records a second poll_run that sees no changes,
    which is noise in the audit trail and nothing worse.
    """
    base_url, key = credentials()
    url = f"{base_url}/rest/v1/rpc/{function_name}"
    body = json.dumps(payload).encode("utf-8")
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    last_error = None
    for attempt in range(1, retries + 1):
        request = urllib.request.Request(url, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=timeout, context=CTX) as response:
                raw = response.read().decode()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:500]
            # 4xx is our bug — a bad payload, a revoked key, a missing grant.
            # Retrying it just repeats the mistake more slowly.
            if 400 <= exc.code < 500:
                raise RuntimeError(f"{function_name}: HTTP {exc.code}: {detail}") from exc
            last_error = RuntimeError(f"{function_name}: HTTP {exc.code}: {detail}")
        except (urllib.error.URLError, TimeoutError, ssl.SSLError, ConnectionError) as exc:
            last_error = RuntimeError(f"{function_name}: {type(exc).__name__}: {exc}")

        if attempt < retries:
            time.sleep(2 ** attempt)

    raise last_error


def ingest(payload):
    """Hand one board fetch to the database. Returns the run summary."""
    return call_rpc("ingest_ats_board", {"payload": payload})


def active_boards(limit=None):
    """The poll list, least-recently-succeeded first."""
    return call_rpc("pipeline_active_boards", {"limit_count": limit}) or []
