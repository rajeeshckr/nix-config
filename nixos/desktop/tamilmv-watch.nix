{ config, lib, pkgs, ... }:

# tamilmv-watch — a Friday "what's new" digest for 1TamilMV, with a
# human-in-the-loop add-to-transmission flow driven from OpenClaw chat.
#
# What this gives you:
#   Every Friday a systemd timer scrapes the 1TamilMV language forums you care
#   about, keeps only topics posted in the last 7 days, and records them as a
#   "pending" digest. Nothing is downloaded automatically. You then open the
#   OpenClaw chat on your phone and ask "what's new on tamilmv?"; the agent runs
#   `tamilmv-pending`, shows you the list, and only when you confirm a title does
#   it run `tamilmv-grab <id>` to push that topic's magnet into transmission.
#
# Flow:
#   Friday 18:00 ─► systemd timer ─► `tamilmv-scan`
#                                       │ scrapes forums 9/22/34/56 (Ta/Te/Ma/Hi)
#                                       │ filters to last 7 days, dedups
#                                       ▼
#                            /var/lib/tamilmv-watch/pending.json
#                                       ▲                   │
#       you, in OpenClaw chat ──────────┘                   │ `tamilmv-grab <id>`
#         "what's new?" → `tamilmv-pending`                 ▼
#                                              transmission RPC :9091
#                                              add magnet → /media/downloads
#
# Why scrape (not RSS): the IPS forum's `.xml` endpoint returns HTML, not a
# feed. Each language is a numbered forum; each topic page carries the actual
# `magnet:` links (one per quality/size). We parse the forum listing for recent
# topics, then fetch the chosen topic on demand to resolve magnets.
#
# LEGAL/ETHICAL: this automates *your* manual browsing of a torrent indexer.
# It is opt-in per title (you confirm each one). Seeding/availability and the
# legality of any given torrent are on you; nothing here is automatic.

let
  stateDir = "/var/lib/tamilmv-watch";

  # Base host — a *fallback default* only. Mirrors rotate
  # (durban/fi/center/...); the scraper auto-discovers the live mirror at run
  # time via `redirectorUrl` below, so this rarely needs touching. If the
  # redirector itself ever dies, the agent (or you) updates this to the current
  # mirror and commits — see the OpenClaw AGENTS.md "1TamilMV" section.
  baseUrl = "https://www.1tamilmv.durban";

  # Ordered seed list for live-mirror discovery. These are the operator's known
  # "signpost" domains: stable redirectors (`.fi`) and recent mirrors. Each is
  # tried in turn — followed through redirects, then *validated* as the real
  # IPS forum (see the resolver below) — and the first that proves itself wins.
  # This covers the "both stale" case (the previous fallback was wrong AND the
  # primary redirector is down) without blindly trusting any domain we hit.
  #
  # We deliberately do NOT brute-force the DNS namespace: it's infeasible and
  # unsafe (parked pages, ISP block-pages, and phishing clones serving fake
  # magnets all "resolve"). When ALL seeds fail, the agent/you add the newly
  # announced domain (from their Telegram/email) to the FRONT of this list and
  # commit — see the OpenClaw AGENTS.md "1TamilMV" section.
  seeds = [
    "https://www.1tamilmv.fi"
    "https://www.1tamilmv.durban"
    "https://www.1tamilmv.center"
  ];

  seedsJson = builtins.toJSON seeds;

  # Shared logic kept as a real Python module (cleaner than splicing code
  # strings into each heredoc, which fights Nix's indentation stripping):
  # mirror resolution, magnet/transmission grab, and wishlist matching. Every
  # CLI imports it via PYTHONPATH (set below). The file is `git add`-ed so the
  # flake can read it.
  commonModule = pkgs.runCommand "tamilmv-common" { } ''
    mkdir -p "$out"
    cp ${./scripts/tamilmv_common.py} "$out/tamilmv_common.py"
  '';

  # download dir + RPC endpoint, shared by grab CLI and scan auto-grab.
  downloadDir = "/media/downloads";
  rpcUrl = "http://127.0.0.1:9091/transmission/rpc";

  # PYTHONPATH wrapper arg every script gets.
  pyPath = [ "--prefix" "PYTHONPATH" ":" "${commonModule}" ];

  # Languages selected by the human: Tamil, Telugu, Malayalam, Hindi.
  # Map of forum-id -> human label. IDs are stable IPS forum node ids.
  forums = {
    "9" = "Tamil";
    "22" = "Telugu";
    "34" = "Malayalam";
    "56" = "Hindi";
  };

  forumsJson = builtins.toJSON forums;

  # How far back a topic counts as "this week".
  windowDays = 7;

  # Default quality to grab when the human doesn't specify one.
  defaultQuality = "1080p";

  ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    + "(KHTML, like Gecko) Chrome/120.0 Safari/537.36";

  pyEnv = pkgs.python3;

  # --- tamilmv-scan: refresh the pending digest -----------------------------
  # Fetches each forum listing, parses topic links + their <time datetime=…>,
  # keeps topics within the window, merges into pending.json (preserving any
  # already-grabbed/dismissed state), and prints a short summary.
  tamilmvScan = pkgs.writers.writePython3Bin "tamilmv-scan"
    {
      libraries = [ ];
      flakeIgnore = [ "E501" "W503" "E226" "E302" "E305" "E306" ];
      makeWrapperArgs = pyPath;
    } ''
    import json
    import os
    import re
    import sys
    from datetime import datetime, timezone, timedelta

    import tamilmv_common as tc

    FALLBACK_BASE = ${builtins.toJSON baseUrl}
    SEEDS = json.loads(${builtins.toJSON seedsJson})
    FORUMS = json.loads(${builtins.toJSON forumsJson})
    WINDOW = timedelta(days=${toString windowDays})
    STATE_DIR = ${builtins.toJSON stateDir}
    PENDING = os.path.join(STATE_DIR, "pending.json")
    UA = ${builtins.toJSON ua}
    DEFAULT_QUALITY = ${builtins.toJSON defaultQuality}
    DOWNLOAD_DIR = ${builtins.toJSON downloadDir}
    RPC = ${builtins.toJSON rpcUrl}

    TOPIC_RE = re.compile(
        r'index\.php\?/forums/topic/(\d+)-([a-z0-9%-]+)', re.I)
    # IPS renders each row's time as: <time datetime='2026-06-21T06:34:13Z' ...>
    TIME_RE = re.compile(r"datetime='([0-9T:+\-Z]+)'")

    def fetch(url):
        return tc.fetch(url, UA)

    def parse_forum(html, lang, base):
        """Yield (topic_id, slug, posted_dt) for topics in this listing.

        We walk the HTML once; the topic anchor and its sibling <time> appear
        close together per row, so we pair each topic id with the *next* time
        stamp that follows it. Topics with no following time (edge of page) are
        skipped rather than guessed.
        """
        out = {}
        # Tokenize into (kind, value, position) for topics and times.
        events = []
        for m in TOPIC_RE.finditer(html):
            tid = m.group(1)
            slug = m.group(2)
            # The synthetic "<id>-0" anchors are section headers, not topics.
            if slug == "0":
                continue
            events.append((m.start(), "topic", (tid, slug)))
        for m in TIME_RE.finditer(html):
            events.append((m.start(), "time", m.group(1)))
        events.sort()

        pending_topic = None
        for _pos, kind, val in events:
            if kind == "topic":
                pending_topic = val
            elif kind == "time" and pending_topic is not None:
                tid, slug = pending_topic
                try:
                    dt = datetime.fromisoformat(val.replace("Z", "+00:00"))
                except ValueError:
                    pending_topic = None
                    continue
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                # Keep the *first* (newest, listing is reverse-chronological)
                # time we see for a given topic id.
                if tid not in out:
                    out[tid] = {
                        "id": tid,
                        "slug": slug,
                        "lang": lang,
                        "title": slug_to_title(slug),
                        "url": f"{base}/index.php?/forums/topic/{tid}-{slug}/",
                        "posted": dt.isoformat(),
                    }
                pending_topic = None
        return out

    def slug_to_title(slug):
        # Slugs are url-ish: "194310-cup-2026-tamil-true-web-dl-1080p..."
        import urllib.parse
        s = urllib.parse.unquote(slug)
        return s.replace("-", " ").strip()

    def main():
        os.makedirs(STATE_DIR, exist_ok=True)
        now = datetime.now(timezone.utc)
        cutoff = now - WINDOW

        # Auto-discover the live mirror by walking the validated seed list
        # (the hop Chrome follows, plus fallbacks). Persist it so
        # `tamilmv-grab` resolves topic URLs against the same mirror.
        base, source = tc.resolve_base(SEEDS, FALLBACK_BASE, UA)

        # Load existing pending so we keep per-topic state (grabbed/dismissed)
        # and don't re-surface things you've already actioned this week.
        try:
            with open(PENDING) as f:
                state = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            state = {"updated": None, "items": {}}
        items = state.get("items", {})

        found = 0
        errors = []
        for fid, lang in FORUMS.items():
            url = f"{base}/index.php?/forums/forum/{fid}-{lang.lower()}-language/"
            try:
                html = fetch(url)
            except Exception as e:  # noqa: BLE001 — report, keep going
                errors.append(f"{lang}: {e}")
                continue
            for tid, rec in parse_forum(html, lang, base).items():
                posted = datetime.fromisoformat(rec["posted"])
                if posted < cutoff:
                    continue
                found += 1
                existing = items.get(tid)
                if existing is None:
                    rec["status"] = "new"
                    rec["seen"] = now.isoformat()
                    items[tid] = rec
                else:
                    # Refresh metadata but preserve action status.
                    existing.update({k: rec[k] for k in
                                     ("title", "url", "posted", "lang")})

        # Drop items that have aged out of the window AND were never actioned,
        # so pending.json stays a "this week" view.
        for tid in list(items.keys()):
            it = items[tid]
            posted = datetime.fromisoformat(it["posted"])
            if posted < cutoff and it.get("status") in (None, "new"):
                del items[tid]

        # --- Wishlist auto-grab ------------------------------------------
        # For each ACTIVE wishlist entry, find the newest in-window item it
        # matches and grab it straight into transmission (no confirmation —
        # this is the deliberate exception to the "always ask" rule, opt-in
        # per wishlist entry). Fulfill-once: a matched entry is marked
        # fulfilled and stops matching.
        wl = tc.load_wishlist(STATE_DIR)
        grabbed_report = []
        for entry in wl.get("items", []):
            if entry.get("status") != "active":
                continue
            cands = [it for it in items.values() if tc.wish_matches(entry, it)]
            if not cands:
                continue
            cands.sort(key=lambda it: it.get("posted", ""), reverse=True)
            it = cands[0]
            res = tc.grab_topic(it["url"], entry.get("quality"),
                                ua=UA, rpc=RPC, download_dir=DOWNLOAD_DIR)
            if res.get("ok"):
                it["status"] = "grabbed"
                it["grabbed_magnet"] = res["name"]
                it["grabbed_at"] = now.isoformat()
                it["grabbed_by"] = f"wishlist:{entry['id']}"
                entry["status"] = "fulfilled"
                entry["fulfilled_topic"] = it["id"]
                entry["fulfilled_at"] = now.isoformat()
                entry["fulfilled_name"] = res["name"]
                verb = "already in transmission" if res.get("duplicate") \
                    else "auto-grabbed"
                grabbed_report.append(
                    f"  [{entry['raw']}] -> {verb}: {res['name']}")
            else:
                grabbed_report.append(
                    f"  [{entry['raw']}] -> match {it['id']} but grab "
                    f"FAILED: {res.get('error')}")
        if grabbed_report:
            tc.save_wishlist(STATE_DIR, wl)

        state["items"] = items
        state["updated"] = now.isoformat()
        state["base"] = base
        with open(PENDING, "w") as f:
            json.dump(state, f, indent=2)

        new_n = sum(1 for it in items.values() if it.get("status") == "new")
        print(f"tamilmv-scan: {found} topics in last "
              f"${toString windowDays}d across {len(FORUMS)} forums; "
              f"{new_n} not-yet-actioned. (mirror: {base} via {source})")
        if grabbed_report:
            print(f"tamilmv-scan: wishlist auto-grab "
                  f"({len(grabbed_report)}):")
            for line in grabbed_report:
                print(line)
        # Surface mirror drift so the agent/you can update the compiled-in
        # fallback in tamilmv-watch.nix and commit (see AGENTS.md). This is
        # informational only — scans keep working via the seed list.
        if source == "stale":
            print("tamilmv-scan: WARNING — every known seed AND the "
                  "compiled-in fallback failed validation. The site may have "
                  "moved to a domain we don't know yet; add the newly "
                  "announced domain to `seeds` in "
                  "nixos/desktop/tamilmv-watch.nix and commit.",
                  file=sys.stderr)
        elif base != FALLBACK_BASE:
            print(f"tamilmv-scan: NOTE — live mirror {base} differs from the "
                  f"compiled-in fallback {FALLBACK_BASE}. Consider updating "
                  f"`baseUrl` in nixos/desktop/tamilmv-watch.nix and "
                  f"committing.", file=sys.stderr)
        if errors:
            print("errors:", file=sys.stderr)
            for e in errors:
                print("  " + e, file=sys.stderr)

    if __name__ == "__main__":
        main()
  '';

  # --- tamilmv-pending: show the digest -------------------------------------
  # Human/agent-facing: prints the not-yet-actioned topics grouped by language,
  # one per line with its id so you can say "grab 198539".
  tamilmvPending = pkgs.writers.writePython3Bin "tamilmv-pending"
    {
      flakeIgnore = [ "E501" "E302" "E305" "E306" ];
    } ''
    import json
    import os
    import sys
    from datetime import datetime

    STATE_DIR = ${builtins.toJSON stateDir}
    PENDING = os.path.join(STATE_DIR, "pending.json")

    def main():
        show_all = "--all" in sys.argv
        as_json = "--json" in sys.argv
        try:
            with open(PENDING) as f:
                state = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            print("No digest yet. Run `tamilmv-scan` first "
                  "(it also runs automatically on Fridays).")
            return

        items = list(state.get("items", {}).values())
        if not show_all:
            items = [it for it in items if it.get("status") == "new"]
        items.sort(key=lambda it: it.get("posted", ""), reverse=True)

        if as_json:
            print(json.dumps(items, indent=2))
            return

        updated = state.get("updated")
        when = ""
        if updated:
            dt = datetime.fromisoformat(updated)
            when = f" (scanned {dt.astimezone().strftime('%a %d %b %H:%M')})"
        if not items:
            print(f"Nothing new on 1TamilMV this week{when}.")
            return

        print(f"New on 1TamilMV this week{when} "
              f"— {len(items)} item(s). Say e.g. \"grab <id>\":\n")
        by_lang = {}
        for it in items:
            by_lang.setdefault(it.get("lang", "?"), []).append(it)
        for lang in sorted(by_lang):
            print(f"== {lang} ==")
            for it in by_lang[lang]:
                tag = "" if it.get("status") == "new" else f" [{it['status']}]"
                print(f"  [{it['id']}] {it['title']}{tag}")
            print()

    if __name__ == "__main__":
        main()
  '';

  # --- tamilmv-grab: resolve magnets and add to transmission ----------------
  # Fetches a topic page, extracts magnet links, picks one matching the desired
  # quality (default 1080p; falls back to the largest/first if none match),
  # adds it to transmission via RPC, and marks the item grabbed.
  tamilmvGrab = pkgs.writers.writePython3Bin "tamilmv-grab"
    {
      flakeIgnore = [ "E501" "W503" "E226" "E302" "E305" "E306" ];
      makeWrapperArgs = pyPath;
    } ''
    import argparse
    import json
    import os
    import re
    import sys
    from datetime import datetime, timezone

    import tamilmv_common as tc

    FALLBACK_BASE = ${builtins.toJSON baseUrl}
    STATE_DIR = ${builtins.toJSON stateDir}
    PENDING = os.path.join(STATE_DIR, "pending.json")
    UA = ${builtins.toJSON ua}
    DEFAULT_QUALITY = ${builtins.toJSON defaultQuality}
    RPC = ${builtins.toJSON rpcUrl}
    DOWNLOAD_DIR = ${builtins.toJSON downloadDir}

    def load_state():
        try:
            with open(PENDING) as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return {"updated": None, "items": {}}

    def topic_url(tid, state):
        it = state.get("items", {}).get(tid)
        if it and it.get("url"):
            return it["url"]
        # Fall back to an id URL with a placeholder slug, against the mirror the
        # last scan resolved (state["base"]) or the compiled-in default. IPS
        # redirects `<id>-<anything>` to the canonical topic, but ONLY when the
        # slug is non-empty (`<id>-/` lands on the board index with no magnets).
        base = state.get("base") or FALLBACK_BASE
        return f"{base}/index.php?/forums/topic/{tid}-x/"

    def main():
        ap = argparse.ArgumentParser(
            description="Add a 1TamilMV topic's torrent to transmission.")
        ap.add_argument("topic_id",
                        help="numeric topic id from `tamilmv-pending`")
        ap.add_argument("quality", nargs="?", default=DEFAULT_QUALITY,
                        help=f"quality substring to prefer "
                             f"(default {DEFAULT_QUALITY}; 'any' = largest)")
        ap.add_argument("--list", action="store_true",
                        help="just list magnets on the topic, add nothing")
        args = ap.parse_args()

        tid = re.sub(r"\D", "", args.topic_id)
        if not tid:
            print("error: topic id must be numeric", file=sys.stderr)
            sys.exit(2)
        quality = None if args.quality.lower() == "any" else args.quality

        state = load_state()
        url = topic_url(tid, state)

        if args.list:
            try:
                page = tc.fetch(url, UA)
            except Exception as e:  # noqa: BLE001
                print(f"error: could not fetch topic {tid}: {e}",
                      file=sys.stderr)
                sys.exit(1)
            magnets = tc.extract_magnets(page)
            if not magnets:
                print(f"No magnets found on topic {tid}.", file=sys.stderr)
                sys.exit(1)
            for m in magnets:
                print(f"{tc.magnet_size(m)/1e9:5.2f}GB  {tc.magnet_name(m)}")
            return

        res = tc.grab_topic(url, quality, ua=UA, rpc=RPC,
                            download_dir=DOWNLOAD_DIR)
        if not res.get("ok"):
            print(f"error: {res.get('error')}", file=sys.stderr)
            sys.exit(1)
        verb = "already in transmission" if res.get("duplicate") \
            else "added to transmission"
        print(f"{verb}: {res['name']} -> {DOWNLOAD_DIR}")

        # Mark the item grabbed so it drops off the pending list.
        it = state.get("items", {}).get(tid)
        if it is not None:
            it["status"] = "grabbed"
            it["grabbed_magnet"] = res["name"]
            it["grabbed_at"] = datetime.now(timezone.utc).isoformat()
            with open(PENDING, "w") as f:
                json.dump(state, f, indent=2)

    if __name__ == "__main__":
        main()
  '';

  # --- tamilmv-search: find any title on TamilMV (any day, any age) ---------
  # Unlike `tamilmv-pending` (which only shows the last weekly scan), this hits
  # the forum's guest search so the agent can fulfil "download <movie>" for
  # arbitrary/older titles. Prints id-tagged matches; the human picks, the
  # agent runs `tamilmv-grab <id>`.
  tamilmvSearch = pkgs.writers.writePython3Bin "tamilmv-search"
    {
      flakeIgnore = [ "E501" "E302" "E305" "E306" ];
      makeWrapperArgs = pyPath;
    } ''
    import argparse
    import json
    import sys

    import tamilmv_common as tc

    FALLBACK_BASE = ${builtins.toJSON baseUrl}
    SEEDS = json.loads(${builtins.toJSON seedsJson})
    UA = ${builtins.toJSON ua}

    def run_search(base, query, limit):
        try:
            return tc.search_topics(base, query, UA, limit=limit)
        except Exception as e:  # noqa: BLE001
            print(f"error: search failed: {e}", file=sys.stderr)
            sys.exit(1)

    def main():
        ap = argparse.ArgumentParser(
            description="Search 1TamilMV for a title.")
        ap.add_argument("query", nargs="+", help="words to search for")
        ap.add_argument("--limit", type=int, default=15)
        ap.add_argument("--json", action="store_true")
        ap.add_argument("--no-fuzzy", action="store_true",
                        help="don't fall back to a Wikipedia spell-correct")
        args = ap.parse_args()
        query = " ".join(args.query).strip()

        base, source = tc.resolve_base(SEEDS, FALLBACK_BASE, UA)
        results = run_search(base, query, args.limit)
        used = query
        corrected_from = None
        # All Wikipedia spell-correct candidates we considered, so the agent
        # can offer alternatives instead of trusting one (a typo like "athradi"
        # can resolve to the WRONG film — Athadu vs Athiradi).
        suggestions = []

        # Spell-correct fallback: 1TamilMV's search is literal (a typo like
        # "drishyaam" returns nothing), so when the raw query is empty we ask
        # Wikipedia for the canonical title and retry with that.
        if not results and not args.no_fuzzy:
            suggestions = tc.wikipedia_suggest(query, UA)
            for cand in suggestions:
                if cand.lower() == query.lower():
                    continue
                r = run_search(base, cand, args.limit)
                if r:
                    results, used, corrected_from = r, cand, query
                    break

        if args.json:
            print(json.dumps({"query": query, "used": used,
                              "corrected_from": corrected_from,
                              "suggestions": suggestions,
                              "results": results}, indent=2))
            return
        if not results:
            print(f'No results on 1TamilMV for "{query}".')
            if suggestions:
                print(f'  (tried spell-corrections: {", ".join(suggestions)})')
            return
        if corrected_from:
            print(f'No exact match for "{corrected_from}"; showing results '
                  f'for "{used}" (spell-corrected).')
            others = [s for s in suggestions if s.lower() != used.lower()]
            if others:
                print(f'  NOTE: other possible titles for "{corrected_from}": '
                      f'{", ".join(others)} — confirm with the human if '
                      f'unsure this is the right movie.')
            print()
        else:
            print(f'1TamilMV search "{used}" — '
                  f'{len(results)} result(s) (mirror {base}). '
                  f'Say e.g. "grab <id>":\n')
        for r in results:
            print(f"  [{r['id']}] {r['title']}")

    if __name__ == "__main__":
        main()
  '';

  # --- tamilmv-mirror: report the live mirror -------------------------------
  # Walks the validated seed list (same resolver as the scan), reports which
  # source won and whether it drifts from the compiled-in fallback. The agent
  # uses this to decide whether to update + commit `baseUrl` / `seeds`.
  # `--check` exits non-zero when the live mirror differs from the fallback
  # (handy for the agent to branch on); exit 3 when nothing validates at all.
  tamilmvMirror = pkgs.writers.writePython3Bin "tamilmv-mirror"
    {
      flakeIgnore = [ "E501" "E302" "E305" "E306" ];
      makeWrapperArgs = pyPath;
    } ''
    import json
    import sys

    import tamilmv_common as tc

    FALLBACK_BASE = ${builtins.toJSON baseUrl}
    SEEDS = json.loads(${builtins.toJSON seedsJson})
    UA = ${builtins.toJSON ua}

    def main():
        check = "--check" in sys.argv
        live, source = tc.resolve_base(SEEDS, FALLBACK_BASE, UA)
        print(f"live mirror: {live}  (via {source})")
        print(f"seeds tried (in order): {', '.join(SEEDS)}")
        print(f"compiled-in fallback (baseUrl in tamilmv-watch.nix): "
              f"{FALLBACK_BASE}")
        if source == "stale":
            print("=> STALE: no seed and not even the fallback validated as "
                  "the IPS forum. The site likely moved to an unknown domain. "
                  "Find the new domain (their Telegram/email), add it to the "
                  "FRONT of `seeds` in nixos/desktop/tamilmv-watch.nix, and "
                  "commit.")
            sys.exit(3)
        drift = live != FALLBACK_BASE
        if drift:
            print("=> DRIFT: the live mirror differs from the compiled-in "
                  "fallback. To make it the default, edit `baseUrl` in "
                  "nixos/desktop/tamilmv-watch.nix and commit.")
        else:
            print("=> in sync.")
        if check and drift:
            sys.exit(1)

    if __name__ == "__main__":
        main()
  '';

  # --- tamilmv-wish-add: add a wishlist entry -------------------------------
  # `tamilmv-wish-add Athiradi malayalam` (or quote it). A recognized language
  # word becomes a language filter; a quality token (720p/1080p/4k) becomes the
  # preferred quality; the rest are title terms that must all appear in a
  # release title. Active entries are auto-grabbed by the weekly scan.
  tamilmvWishAdd = pkgs.writers.writePython3Bin "tamilmv-wish-add"
    {
      flakeIgnore = [ "E501" "W503" "E302" "E305" "E306" ];
      makeWrapperArgs = pyPath;
    } ''
    import secrets
    import sys
    from datetime import datetime, timezone

    import tamilmv_common as tc

    STATE_DIR = ${builtins.toJSON stateDir}
    DEFAULT_QUALITY = ${builtins.toJSON defaultQuality}

    def main():
        phrase = " ".join(sys.argv[1:]).strip()
        if not phrase:
            print('usage: tamilmv-wish-add <title terms> [language] '
                  '[quality]\\n  e.g. tamilmv-wish-add Athiradi malayalam',
                  file=sys.stderr)
            sys.exit(2)
        parsed = tc.parse_wish_phrase(phrase, DEFAULT_QUALITY)
        if not parsed["terms"]:
            print("error: need at least one title word (besides a language/"
                  "quality word).", file=sys.stderr)
            sys.exit(2)
        wl = tc.load_wishlist(STATE_DIR)
        # De-dupe: same terms+lang already active -> no-op.
        for e in wl["items"]:
            if (e.get("status") == "active"
                    and e.get("terms") == parsed["terms"]
                    and e.get("lang") == parsed["lang"]):
                print(f"already on wishlist: [{e['id']}] {e['raw']}")
                return
        entry = dict(parsed)
        entry["id"] = secrets.token_hex(3)
        entry["status"] = "active"
        entry["added"] = datetime.now(timezone.utc).isoformat()
        wl["items"].append(entry)
        tc.save_wishlist(STATE_DIR, wl)
        lang = entry["lang"] or "any language"
        print(f"added to wishlist [{entry['id']}]: "
              f"terms={entry['terms']} lang={lang} quality={entry['quality']}")
        print("It will be auto-grabbed when a matching release appears in a "
              "weekly scan.")

    if __name__ == "__main__":
        main()
  '';

  # --- tamilmv-wishlist: list wishlist entries ------------------------------
  tamilmvWishlist = pkgs.writers.writePython3Bin "tamilmv-wishlist"
    {
      flakeIgnore = [ "E501" "E302" "E305" "E306" ];
      makeWrapperArgs = pyPath;
    } ''
    import sys

    import tamilmv_common as tc

    STATE_DIR = ${builtins.toJSON stateDir}

    def main():
        show_all = "--all" in sys.argv
        wl = tc.load_wishlist(STATE_DIR)
        items = wl.get("items", [])
        if not show_all:
            items = [e for e in items if e.get("status") == "active"]
        if not items:
            print("Wishlist is empty. Add one with "
                  "`tamilmv-wish-add <title> [language] [quality]`.")
            return
        for e in items:
            lang = e.get("lang") or "any"
            extra = ""
            if e.get("status") == "fulfilled":
                extra = f"  [fulfilled: {e.get('fulfilled_name', '?')}]"
            print(f"[{e['id']}] {e['raw']}  "
                  f"(terms={e['terms']}, lang={lang}, "
                  f"quality={e.get('quality')}){extra}")

    if __name__ == "__main__":
        main()
  '';

  # --- tamilmv-wish-rm: remove a wishlist entry by id -----------------------
  tamilmvWishRm = pkgs.writers.writePython3Bin "tamilmv-wish-rm"
    {
      flakeIgnore = [ "E501" "E302" "E305" "E306" ];
      makeWrapperArgs = pyPath;
    } ''
    import sys

    import tamilmv_common as tc

    STATE_DIR = ${builtins.toJSON stateDir}

    def main():
        if len(sys.argv) < 2:
            print("usage: tamilmv-wish-rm <id> [<id> ...]", file=sys.stderr)
            sys.exit(2)
        ids = set(sys.argv[1:])
        wl = tc.load_wishlist(STATE_DIR)
        before = len(wl["items"])
        removed = [e for e in wl["items"] if e["id"] in ids]
        wl["items"] = [e for e in wl["items"] if e["id"] not in ids]
        if len(wl["items"]) == before:
            print(f"no wishlist entry matched id(s): {', '.join(ids)}",
                  file=sys.stderr)
            sys.exit(1)
        tc.save_wishlist(STATE_DIR, wl)
        for e in removed:
            print(f"removed [{e['id']}] {e['raw']}")

    if __name__ == "__main__":
        main()
  '';
in
{
  # The CLIs live on PATH for both you (interactive) and the openclaw agent.
  environment.systemPackages = [
    tamilmvScan
    tamilmvPending
    tamilmvGrab
    tamilmvSearch
    tamilmvMirror
    tamilmvWishAdd
    tamilmvWishlist
    tamilmvWishRm
    pyEnv
  ];

  # Shared state dir, group-readable so the openclaw agent can read the digest
  # and (re)write status when it grabs something. `media` is overkill; we use a
  # dedicated dir owned by openclaw since the agent is the primary actor.
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0775 openclaw openclaw - -"
  ];

  # Friday digest. Collects only — never downloads. `tamilmv-scan` is cheap
  # (4 HTTP GETs) so a missed run (box asleep) is caught by Persistent=true.
  systemd.services.tamilmv-scan = {
    description = "Scan 1TamilMV forums for this week's new releases";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "openclaw";
      Group = "openclaw";
      ExecStart = "${tamilmvScan}/bin/tamilmv-scan";
    };
  };

  systemd.timers.tamilmv-scan = {
    description = "Weekly (Friday) 1TamilMV new-release scan";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Fri 18:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
