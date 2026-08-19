"""Find a company's ATS boards and put them on the watchlist.

Board tokens are discovered, never derived. Greenhouse and Ashby slugs usually
match the company name; Lever's frequently do not — eventbrite, kickstarter,
quora, mixpanel and box all 404'd on 2026-08-17 — so a token is a fact observed
once and then stored, not a string reconstructed each run.

Discovery is just a poll that happens to be the first one: a slug that answers
is registered along with everything currently on its board, which means the
clock on that company starts the moment it is found rather than the next
morning.

Usage:

    python -m pipeline.discover --slug pylon --slug knot
    python -m pipeline.discover --slugs-file candidates.txt
    python -m pipeline.discover --from-sample sized_final.json
    python -m pipeline.discover --slug acme --dry-run

`--from-sample` reads the output of scripts/build_sample.py, so the companies
already qualified for the pre-sale sample can be put on the clock directly.
"""

import argparse
import json
import os
import sys
import time

from . import ats, store


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Probe candidate slugs against each ATS and register what answers.")
    parser.add_argument("--slug", action="append", default=[],
                        help="candidate slug (repeatable)")
    parser.add_argument("--slugs-file", default=None,
                        help="file of candidate slugs, one per line or whitespace separated")
    parser.add_argument("--from-sample", default=None, metavar="JSON",
                        help="scripts/build_sample.py output; reads .companies[].company")
    parser.add_argument("--source", choices=ats.SOURCES, action="append", default=None,
                        help="restrict which ATS to probe (repeatable)")
    parser.add_argument("--dry-run", action="store_true",
                        help="report what was found without registering it")
    parser.add_argument("--emit", default=None, metavar="PATH",
                        help="write the ingest payloads to a JSON file instead of "
                             "sending them; replay with pipeline/replay.sql")
    parser.add_argument("--max-open-roles", type=int, default=None, metavar="N",
                        help="skip boards with more than N open roles. Board size is "
                             "the size proxy from scripts/build_sample.py: a company "
                             "posting hundreds of roles has an in-house platform team "
                             "and is not a prospect for a 20-50 person consultancy.")
    parser.add_argument("--delay", type=float, default=0.2,
                        help="seconds between probes (default 0.2)")
    return parser.parse_args(argv)


def _candidates(args):
    slugs = list(args.slug)

    if args.slugs_file:
        # Comments are stripped before splitting. Without this the words in a
        # file's own header get probed as candidate slugs, and any of them that
        # happens to match a real board quietly joins the watchlist.
        with open(args.slugs_file, encoding="utf-8") as handle:
            for line in handle:
                line = line.split("#", 1)[0]
                slugs += line.split()

    if args.from_sample:
        with open(args.from_sample, encoding="utf-8") as handle:
            data = json.load(handle)
        for row in data.get("companies", []):
            slug = row.get("company")
            if slug:
                slugs.append(slug)

    # Order-preserving dedupe: the operator's own ordering is usually
    # meaningful (best candidates first) and worth keeping.
    seen, unique = set(), []
    for slug in slugs:
        slug = slug.strip().lower()
        if slug and slug.isascii() and slug not in seen:
            seen.add(slug)
            unique.append(slug)
    return unique


def discover(slugs, sources=None, dry_run=False, delay=0.2, out=sys.stdout,
             emit=None, max_open_roles=None):
    sources = tuple(sources) if sources else ats.SOURCES
    found, missing, failures, too_big = [], [], [], []
    payloads = [] if emit is not None else None
    total = len(slugs)

    for index, slug in enumerate(slugs, 1):
        hits = ats.discover_boards(slug, sources=sources)

        if not hits:
            missing.append(slug)
            print(f"[{index:>4}/{total}] {slug:<24} -", file=out)
            continue

        for fetch in hits:
            label = f"[{index:>4}/{total}] {slug:<24} {fetch.source:<10}"

            if max_open_roles is not None and len(fetch.postings) > max_open_roles:
                too_big.append({"slug": slug, "source": fetch.source,
                                "postings": len(fetch.postings)})
                print(f"{label} {len(fetch.postings):>4} postings  skipped (too large)",
                      file=out)
                continue

            if payloads is not None:
                payloads.append(fetch.payload(organization_slug=slug))
                print(f"{label} {len(fetch.postings):>4} postings (captured)", file=out)
                found.append({"slug": slug, "source": fetch.source,
                              "postings": len(fetch.postings)})
                continue

            if dry_run:
                print(f"{label} {len(fetch.postings):>4} postings (dry run)", file=out)
                found.append({"slug": slug, "source": fetch.source,
                              "postings": len(fetch.postings)})
                continue

            try:
                summary = store.ingest(fetch.payload(organization_slug=slug))
            except RuntimeError as exc:
                print(f"{label} REGISTER FAILED: {exc}", file=out)
                failures.append({"slug": slug, "source": fetch.source, "error": str(exc)})
                continue

            print(f"{label} {len(fetch.postings):>4} postings  "
                  f"new {summary.get('new', 0):>3}", file=out)
            found.append({"slug": slug, "source": fetch.source,
                          "postings": len(fetch.postings),
                          "new": summary.get("new", 0)})

        if delay and index < total:
            time.sleep(delay)

    if payloads is not None:
        with open(emit, "w", encoding="utf-8") as handle:
            json.dump(payloads, handle, ensure_ascii=False)

    return found, missing, failures, too_big


def main(argv=None):
    args = _parse_args(argv)
    slugs = _candidates(args)

    if not slugs:
        print("Nothing to probe. Pass --slug, --slugs-file or --from-sample.", file=sys.stderr)
        return 2

    try:
        found, missing, failures, too_big = discover(
            slugs, sources=args.source, dry_run=args.dry_run, delay=args.delay,
            emit=args.emit, max_open_roles=args.max_open_roles)
    except store.ConfigError as exc:
        print(exc, file=sys.stderr)
        return 2

    companies = {row["slug"] for row in found}
    verb = "captured" if args.emit else ("found" if args.dry_run else "registered")
    print("")
    print(f"probed      {len(slugs)} slugs")
    print(f"{verb:<11} {len(found)} boards across {len(companies)} companies")
    print(f"no board    {len(missing)}")
    if too_big:
        print(f"too large   {len(too_big)} boards over the open-roles cap")
    if args.emit:
        print(f"written to  {args.emit}")
    if failures:
        print(f"FAILED      {len(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
