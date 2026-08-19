"""The daily poll. This is the thing that cannot be backfilled.

"Open 60+ days" is computable from the ATS's own dates on the day we first
look. "Quietly reposted" and "posted then withdrawn" are not: they only exist
if something watched the board yesterday too. Every day this does not run is
signal permanently lost — which is why it runs on a schedule that does not
depend on anyone remembering (.github/workflows/ingest.yml).

Usage:

    python -m pipeline.poll                    # every active board
    python -m pipeline.poll --limit 25         # the 25 least recently seen
    python -m pipeline.poll --source ashby
    python -m pipeline.poll --board greenhouse:figma
    python -m pipeline.poll --dry-run          # fetch and report, write nothing

Exit codes: 0 all boards ingested, 1 one or more failed to reach the database.
A board that 404s is NOT a failure of this script — it is a recorded fact about
that board, and it closes nothing.
"""

import argparse
import sys
import time

from . import ats, store


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Poll ATS boards into the pipeline schema.")
    parser.add_argument("--limit", type=int, default=None,
                        help="poll only the N least-recently-succeeded boards")
    parser.add_argument("--source", choices=ats.SOURCES, default=None,
                        help="restrict to one ATS")
    parser.add_argument("--board", action="append", default=None, metavar="SOURCE:TOKEN",
                        help="poll one board explicitly, e.g. greenhouse:figma "
                             "(repeatable; skips the watchlist)")
    parser.add_argument("--dry-run", action="store_true",
                        help="fetch and summarise without writing anything")
    parser.add_argument("--delay", type=float, default=0.3,
                        help="seconds between fetches (default 0.3)")
    return parser.parse_args(argv)


def _boards_from_args(args):
    """Either the explicit --board list, or the watchlist from the database."""
    if args.board:
        boards = []
        for item in args.board:
            source, _, token = item.partition(":")
            if source not in ats.SOURCES or not token:
                raise SystemExit(f"--board expects SOURCE:TOKEN, got {item!r}")
            boards.append({"source": source, "board_token": token,
                           "organization_slug": token, "organization_name": None})
        return boards

    boards = store.active_boards(limit=args.limit)
    if args.source:
        boards = [b for b in boards if b["source"] == args.source]
    return boards


def poll(boards, dry_run=False, delay=0.3, out=sys.stdout):
    """Fetch and ingest each board. Returns (results, failures)."""
    results, failures = [], []
    total = len(boards)

    for index, board in enumerate(boards, 1):
        source = board["source"]
        token = board["board_token"]

        fetch = ats.fetch_board(source, token)
        line = f"[{index:>4}/{total}] {source:<10} {token:<24} {fetch.status:<16}"

        if dry_run:
            print(f"{line} {len(fetch.postings):>4} postings (dry run)", file=out)
            results.append({"source": source, "board_token": token,
                            "status": fetch.status, "seen": len(fetch.postings)})
        else:
            payload = fetch.payload(
                organization_slug=board.get("organization_slug") or token,
                organization_name=board.get("organization_name"))
            try:
                summary = store.ingest(payload)
            except RuntimeError as exc:
                # The fetch may have been fine; we simply failed to record it.
                # That is a real failure and must not be mistaken for a quiet
                # day on that board.
                print(f"{line} INGEST FAILED: {exc}", file=out)
                failures.append({"source": source, "board_token": token, "error": str(exc)})
                continue

            print(f"{line} seen {summary.get('seen', 0):>4}"
                  f"  new {summary.get('new', 0):>3}"
                  f"  closed {summary.get('closed', 0):>3}"
                  f"  reopened {summary.get('reopened', 0):>3}"
                  f"  changed {summary.get('changed', 0):>3}", file=out)
            results.append(summary)

        if delay and index < total:
            time.sleep(delay)

    return results, failures


def _summarise(results, failures, dry_run, out=sys.stdout):
    def total(key):
        return sum(r.get(key, 0) or 0 for r in results)

    statuses = {}
    for result in results:
        status = result.get("status", "unknown")
        statuses[status] = statuses.get(status, 0) + 1

    print("", file=out)
    print(f"boards      {len(results)}"
          + (f"  ({', '.join(f'{k}: {v}' for k, v in sorted(statuses.items()))})"
             if statuses else ""), file=out)
    if not dry_run:
        print(f"postings    seen {total('seen')}  new {total('new')}  "
              f"closed {total('closed')}  reopened {total('reopened')}  "
              f"changed {total('changed')}", file=out)
    if failures:
        print(f"FAILED      {len(failures)} board(s) could not be written:", file=out)
        for failure in failures:
            print(f"            {failure['source']}:{failure['board_token']} "
                  f"- {failure['error'][:160]}", file=out)

    # Loud, because it is the failure mode that costs the most: a board that
    # answers but answers with nothing, while we hold open postings for it.
    unexpected = statuses.get("empty_unexpected", 0)
    if unexpected:
        print(f"REVIEW      {unexpected} board(s) returned nothing while holding open "
              f"postings - check pipeline.board_health; nothing was closed.", file=out)


def main(argv=None):
    args = _parse_args(argv)

    try:
        boards = _boards_from_args(args)
    except store.ConfigError as exc:
        print(exc, file=sys.stderr)
        return 2

    if not boards:
        print("No active boards to poll. Register some first: "
              "python -m pipeline.discover --slug <slug>", file=sys.stderr)
        return 0

    results, failures = poll(boards, dry_run=args.dry_run, delay=args.delay)
    _summarise(results, failures, args.dry_run)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
