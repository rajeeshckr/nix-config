"""Shared logic for the tamilmv-watch tooling.

Imported by `tamilmv-scan`, `tamilmv-grab`, `tamilmv-mirror`, and the
`tamilmv-wish-*` CLIs (placed on PYTHONPATH by the Nix module). Keeping this in
one real module avoids duplicating the network/parsing/transmission code across
the heredoc-defined scripts.

Contents:
  - Live-mirror resolution (validated seed walk).
  - Magnet extraction + quality picking + transmission RPC add (the guts of
    `tamilmv-grab`, reused by the wishlist auto-grab in the weekly scan).
  - Wishlist load/save + matching.

Config (seeds, fallback base, UA, download dir, RPC url) is passed in by the
caller rather than read from globals, so there's no hidden coupling.
"""

import html as htmllib
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request

# Forum-9 (Tamil) listing: a stable, content-bearing page we already scrape.
VALIDATE_PATH = "/index.php?/forums/forum/9-tamil-language/"

# Languages we recognize as a *filter* word in a wishlist phrase. Lowercased.
KNOWN_LANGS = {
    "tamil", "telugu", "malayalam", "hindi", "kannada", "english",
}

_MAGNET_STOP = chr(34) + chr(39) + "<>\\" + " \t\r\n"
MAGNET_RE = re.compile("magnet:[?][^" + re.escape(_MAGNET_STOP) + "]+")


# --- HTTP -----------------------------------------------------------------

def fetch(url, ua, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


# --- mirror resolution ----------------------------------------------------

def _origin(url):
    p = urllib.parse.urlparse(url)
    return f"{p.scheme}://{p.netloc}" if p.scheme and p.netloc else None


def validate(base, ua, timeout=20):
    """True iff `base` serves our IPS forum (not a clone/park/block page)."""
    try:
        req = urllib.request.Request(base + VALIDATE_PATH,
                                     headers={"User-Agent": ua})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            if r.status != 200:
                return False
            has_ips = r.headers.get("x-ips-loggedin") is not None
            body = r.read(200000).decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 — any failure means "not valid"
        return False
    return has_ips and ("forums/topic/" in body)


def resolve_base(seeds, fallback_base, ua, timeout=20):
    """Discover the current live mirror, validated. Returns (base, source).

    Walks `seeds` in order, following each through redirects and validating it.
    First that validates wins. Else the `fallback_base` (if it still
    validates). `source` is the winning seed URL, "fallback", or "stale".
    """
    import sys
    tried = []
    for seed in seeds:
        try:
            req = urllib.request.Request(seed + "/",
                                         headers={"User-Agent": ua})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                base = _origin(r.geturl())
        except Exception as e:  # noqa: BLE001
            tried.append(f"{seed} (unreachable: {e})")
            continue
        if base and validate(base, ua, timeout):
            return base, seed
        tried.append(f"{seed} -> {base} (failed validation)")
    if validate(fallback_base, ua, timeout):
        return fallback_base, "fallback"
    print("tamilmv: no seed validated and the compiled-in fallback is also "
          "unreachable. Tried:\n  " + "\n  ".join(tried), file=sys.stderr)
    return fallback_base, "stale"


# --- magnets / transmission ------------------------------------------------

def magnet_name(mag):
    params = urllib.parse.parse_qs(urllib.parse.urlparse(mag).query)
    return urllib.parse.unquote(params.get("dn", [""])[0])


def magnet_size(mag):
    params = urllib.parse.parse_qs(urllib.parse.urlparse(mag).query)
    try:
        return int(params.get("xl", ["0"])[0])
    except ValueError:
        return 0


def extract_magnets(page):
    """Unique magnets on a topic page, in document order (by btih)."""
    out, seen = [], set()
    for raw in MAGNET_RE.findall(page):
        mag = htmllib.unescape(raw)
        btih = urllib.parse.parse_qs(
            urllib.parse.urlparse(mag).query).get("xt", [""])[0]
        if btih and btih not in seen:
            seen.add(btih)
            out.append(mag)
    return out


def pick_magnet(magnets, quality):
    """Choose the best magnet for `quality` (substring), else the largest."""
    if not magnets:
        return None
    if quality:
        ql = quality.lower()
        matches = [m for m in magnets
                   if ql in magnet_name(m).lower() or ql in m.lower()]
        if matches:
            return max(matches, key=magnet_size)
    return max(magnets, key=magnet_size)


def _rpc_session_id(rpc, ua):
    req = urllib.request.Request(rpc, data=b"{}", headers={"User-Agent": ua})
    try:
        urllib.request.urlopen(req, timeout=15)
    except urllib.error.HTTPError as e:
        return e.headers.get("X-Transmission-Session-Id", "")
    return ""


def rpc_add(magnet, rpc, ua, download_dir):
    sid = _rpc_session_id(rpc, ua)
    body = json.dumps({
        "method": "torrent-add",
        "arguments": {"filename": magnet, "download-dir": download_dir},
    }).encode()
    req = urllib.request.Request(
        rpc, data=body,
        headers={"User-Agent": ua, "X-Transmission-Session-Id": sid,
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def grab_topic(topic_url, quality, *, ua, rpc, download_dir):
    """Resolve a topic's magnets, add the chosen one to transmission.

    Returns a dict: {ok, name, duplicate, error}. Does NOT touch any state
    file — the caller records status. `quality` None means "largest".
    """
    try:
        page = fetch(topic_url, ua)
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"fetch failed: {e}"}
    magnets = extract_magnets(page)
    if not magnets:
        return {"ok": False, "error": "no magnets on topic page"}
    chosen = pick_magnet(magnets, quality)
    name = magnet_name(chosen) or "(unnamed)"
    try:
        resp = rpc_add(chosen, rpc, ua, download_dir)
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"transmission add failed: {e}",
                "name": name}
    if resp.get("result") != "success":
        return {"ok": False, "error": f"transmission: {resp.get('result')}",
                "name": name}
    arg = resp.get("arguments", {})
    added = arg.get("torrent-added") or arg.get("torrent-duplicate") or {}
    return {"ok": True, "name": added.get("name", name),
            "duplicate": "torrent-duplicate" in arg}


# --- search ----------------------------------------------------------------

_TOPIC_LINK_RE = re.compile(
    r"index\.php\?/forums/topic/(\d+)-([a-z0-9%-]+)", re.I)


def slug_to_title(slug):
    return urllib.parse.unquote(slug).replace("-", " ").strip()


def _strip_title(name):
    """Drop a trailing '(... film)'/'(YEAR)' parenthetical and trailing year.

    Wikipedia titles look like 'Vikram (2022 film)' or 'Athiradi (2026 film)';
    1TamilMV titles don't carry the parenthetical, so we search the bare name.
    """
    name = re.sub(r"\s*\([^)]*\)\s*$", "", name).strip()
    return name


def wikipedia_suggest(query, ua, limit=3, timeout=15):
    """Return likely canonical movie titles for a (possibly misspelled) query.

    Uses Wikipedia's no-auth OpenSearch API, which has good typo tolerance
    ('drishyaam' -> 'Drishyam'). Returns a list of bare titles (parentheticals
    stripped), best-first. Empty list on any failure — callers fall back to the
    raw query so this never makes search worse.
    """
    try:
        url = ("https://en.wikipedia.org/w/api.php?action=opensearch"
               f"&limit={limit}&namespace=0&format=json"
               f"&search={urllib.parse.quote(query)}")
        body = fetch(url, ua, timeout)
        data = json.loads(body)
        titles = data[1] if len(data) > 1 else []
    except Exception:  # noqa: BLE001
        return []
    out, seen = [], set()
    for t in titles:
        bare = _strip_title(t)
        key = bare.lower()
        if bare and key not in seen:
            seen.add(key)
            out.append(bare)
    return out


def search_topics(base, query, ua, limit=15, timeout=30):
    """Search the IPS forum for `query`, return [{id,slug,title,url}].

    Uses the guest-accessible forum search, restricted to topics, AND-matching
    all words. Results come back in the site's relevance order; we de-dup by
    topic id and keep that order. Slug "<id>-0" anchors (section headers) and
    obvious multi-movie bundles are kept — the caller/human decides.
    """
    q = urllib.parse.quote(query)
    url = (f"{base}/index.php?/search/&q={q}"
           f"&type=forums_topic&search_and_or=and&sortby=relevancy")
    html = fetch(url, ua, timeout)
    out, seen = [], set()
    for m in _TOPIC_LINK_RE.finditer(html):
        tid, slug = m.group(1), m.group(2)
        if slug == "0" or tid in seen:
            continue
        seen.add(tid)
        out.append({
            "id": tid,
            "slug": slug,
            "title": slug_to_title(slug),
            "url": f"{base}/index.php?/forums/topic/{tid}-{slug}/",
        })
        if len(out) >= limit:
            break
    return out


# --- wishlist --------------------------------------------------------------
# wishlist.json shape:
#   {"items": [{"id": "<short>", "terms": ["athiradi"], "lang": "malayalam",
#               "quality": "1080p", "raw": "Athiradi malayalam",
#               "status": "active|fulfilled", "added": "<iso>",
#               "fulfilled_topic": "<id>", "fulfilled_at": "<iso>"}]}

def wishlist_path(state_dir):
    return os.path.join(state_dir, "wishlist.json")


def load_wishlist(state_dir):
    try:
        with open(wishlist_path(state_dir)) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"items": []}
    data.setdefault("items", [])
    return data


def save_wishlist(state_dir, data):
    os.makedirs(state_dir, exist_ok=True)
    with open(wishlist_path(state_dir), "w") as f:
        json.dump(data, f, indent=2)


def parse_wish_phrase(phrase, default_quality):
    """Turn a free-text phrase into a structured wish entry (no id/status).

    Recognizes a trailing/embedded language word (KNOWN_LANGS) as a `lang`
    filter and a quality token (e.g. 720p/1080p/4k) as `quality`; everything
    else becomes title `terms` that must all appear in the release title.
    """
    raw = phrase.strip()
    tokens = raw.split()
    lang = None
    quality = None
    terms = []
    # A "quality" token is either a resolution (1080p/4k/…) or a file-size
    # marker (250mb/700mb/1.3gb/5.2gb) — both appear verbatim in the magnet
    # names, so `pick_magnet`'s substring match can use either to select a
    # specific rip. Anything else is a title term.
    qual_re = re.compile(
        r"^(4k|2160p|1080p|720p|480p|360p|\d+(\.\d+)?(mb|gb))$", re.I)
    for tok in tokens:
        low = tok.lower().strip(",")
        if low in KNOWN_LANGS and lang is None:
            lang = low
        elif qual_re.match(low) and quality is None:
            quality = low
        else:
            terms.append(tok)
    return {
        "raw": raw,
        "terms": [t.lower() for t in terms if t],
        "lang": lang,
        "quality": quality or default_quality,
    }


def wish_matches(entry, item):
    """True iff scan `item` (a topic rec) satisfies wishlist `entry`.

    Title term match: every term must be a substring of the item title.
    Language filter: if the entry has a lang, the item's language must equal it
    (the scan tags each item with the forum's language) OR the lang word must
    appear in the title (covers multi-language releases).
    """
    title = item.get("title", "").lower()
    if not entry.get("terms"):
        return False
    if not all(t in title for t in entry["terms"]):
        return False
    lang = entry.get("lang")
    if lang:
        item_lang = (item.get("lang") or "").lower()
        if lang != item_lang and lang not in title:
            return False
    return True
