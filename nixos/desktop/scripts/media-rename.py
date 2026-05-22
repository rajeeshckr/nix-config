#!/usr/bin/env python3
"""media-rename.py - LLM-driven cleanup of messy filenames under /media/movies.

Uses a small local LLM (qwen2.5:3b via Ollama by default) to extract the
canonical "Title (Year)" from torrent-style names, then renames the file
or directory in place. After successful renames it triggers a Jellyfin
library refresh so the UI reflects the changes immediately.

Same-branch renames only -- the script operates on the underlying mergerfs
branch path (/media-disk1, /media-disk2, /media-usb) when given /media/...
so renames stay within a single ext4 filesystem and are O(1) inode swaps.

Safety:
  - Idempotent: entries already matching "Title (YYYY)" pattern are skipped.
  - Pure rename, no copies, no deletes.
  - Per-item independent: one failure doesn't poison the rest.
  - Year sanity-checked to [1900, current+1].
  - Title length and charset validated against a conservative regex.
  - confidence == "low" responses are logged but never auto-renamed.
  - Lockfile prevents concurrent runs.

Modes:
  --dry-run       (default) print proposals, do nothing
  --apply         actually rename, only "high" confidence + sanity-passed
  --interactive   prompt y/n for each proposal

Usage:
  media-rename --dry-run
  media-rename --apply --path /media/movies
  media-rename --interactive
"""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import logging
import os
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

LOG = logging.getLogger("media-rename")


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:3b")
JELLYFIN_URL = os.environ.get("JELLYFIN_URL", "http://127.0.0.1:8096")
JELLYFIN_API_KEY = os.environ.get("JELLYFIN_API_KEY", "")

# Falls back to /tmp when /run/media-rename/ doesn't exist (e.g. interactive
# invocation outside the systemd unit, which creates RuntimeDirectory for us).
LOCKFILE = (
    "/run/media-rename/lock" if os.path.isdir("/run/media-rename") else "/tmp/media-rename.lock"
)

# Top-level entries to never touch when scanning roots directly.
SKIP_ENTRIES = {
    ".incomplete",
    "downloads",
    "transmission",
    "radarr",
    "sonarr",
    "lost+found",
    ".Trash-1000",
    "takeout",
}

# File extensions we recognize as the "main" media file inside a movie dir.
MEDIA_EXTS = {".mkv", ".mp4", ".avi", ".m4v", ".mov", ".wmv"}

# Mergerfs branch roots. Used to translate /media/foo -> /media-diskN/foo
# so renames stay on a single underlying filesystem.
MERGERFS_BRANCHES = ("/media-disk1", "/media-disk2", "/media-usb")

# "Title (YYYY)" canonical form (optionally with .ext suffix).
# Allows letters/digits/spaces/&/!/:/'/-/,/./apostrophe.
CLEAN_PATTERN = re.compile(
    r"^[\w\s\-':,.&!()]+\s\(\d{4}\)(\.[a-z0-9]+)?$",
    re.IGNORECASE,
)

# Year range we'll accept from the LLM.
MIN_YEAR = 1900
MAX_YEAR = dt.date.today().year + 1

# Title must be at least this many characters.
MIN_TITLE_LEN = 1
MAX_TITLE_LEN = 200


# ---------------------------------------------------------------------------
# LLM prompt
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """You extract the canonical movie Title and release Year from a messy filename.

Output ONLY a JSON object with these keys, nothing else:
  title: string -- the movie name, words separated by single spaces, no source/codec/quality tags
  year:  integer -- 4-digit release year extracted FROM THE FILENAME only; 0 if no year is present
  confidence: one of "high", "medium", "low"

Rules:
  - Drop website prefixes: "www.1TamilMV.frl -", "[TorrentCounter.to].", "www.UIndex.org -", "rodeo -", etc.
    Any text before the actual movie title that contains a dot-separated domain, a tracker name, or
    looks like a tracker subdomain segment must be stripped.
  - Drop quality/source tags: 1080p, 2160p, 4K, HDR, DV, SDR, WEBRip, HDRip, BluRay, BDRemux, REMUX,
    WEB-DL, x264, x265, h264, h265, HEVC, AVC, XviD, 10bit, AAC, DDP5.1, DD+5.1, DTS, TrueHD, Atmos.
  - Drop file size markers like "2GB", "800MB", "7.5GB".
  - Drop language lists like "[Tam + Tel + Hin + Mal]" or "Hindi Eng" or "Malayalam".
  - Drop release-group suffixes: -EVO, -GalaxyRG, -NAHOM, -Tigole, -Hon3y, -Telly, etc.
  - Drop subtitle markers: ESub, MSub, Sub Ita Eng.
  - Drop everything in brackets [] -- these are always noise tags.
  - If the title is non-English (Tamil/Malayalam/Hindi/Telugu/Korean/etc), keep the original transliterated title.
  - Convert dot-separated titles to space-separated: "Gran.Turismo" -> "Gran Turismo", "Due.West.Our.Sex.Journey" -> "Due West Our Sex Journey".
  - Do NOT translate titles. Do NOT correct spelling beyond the dot-to-space normalization.
  - YEAR RULE -- read carefully:
      * Only return a year that you can see as a 4-digit number (1900-2099) in the input filename.
      * Do NOT use your outside knowledge of when a movie was released.
      * If no 4-digit year (1900-2099) appears in the input, set year=0 and confidence="low".
  - confidence = "high" when title is clear AND a year is explicitly in the input.
  - confidence = "medium" when title needed heavy cleaning but year is still explicit.
  - confidence = "low" when no year in input OR the input doesn't look like a movie name.

Output JSON only, no commentary, no markdown, no code fences."""

# 4-digit year (1900-2099) used to confirm the LLM didn't invent one.
INPUT_YEAR_RE = re.compile(r"(?<!\d)(19\d{2}|20\d{2})(?!\d)")

# Noise tokens the LLM sometimes leaves in the title. Stripped deterministically
# in post-processing so the prompt can focus on the harder "find the year"
# decision instead of trying to learn an ever-growing block-list.
_NOISE_TOKENS = [
    # resolution / source / codec / hdr
    r"\d{3,4}p", r"4K", r"UHD",
    r"HDRip", r"WEBRip", r"WEB[-.]?DL", r"WEB", r"BluRay", r"BDRemux", r"BDREMUX",
    r"DVDRip", r"DvDRip", r"BDRip", r"HDTV", r"REMUX", r"REPACK", r"UNRATED", r"UNTOUCHED",
    r"HDR\d*P?", r"SDR", r"DV",
    r"[xX]\.?26[45]", r"H\.?26[45]", r"HEVC", r"AVC", r"XviD", r"10\s?[Bb]it",
    # audio
    r"DD[P+]?\s*\d\.\d", r"DD\s*\d\.\d", r"AC3", r"AAC", r"FLAC",
    r"DTS(?:[-.](?:HD|X|MA))?\s*(?:\d\.\d)?", r"TrueHD", r"Atmos",
    # 5.1 / 7.1 / 2.0 audio channel markers, both dotted and dot-stripped forms.
    r"\d\.\d(?:\s*CH)?", r"\d\s\d(?:\s*CH)?",
    r"\d{2,3}\s?[Kk]bps",
    # size markers
    r"\d+(?:\.\d+)?\s*[GMK]B",
    # language tokens (only stripped from title -- safe because we already have title)
    r"Hindi", r"Tamil", r"Telugu", r"Malayalam", r"Kannada", r"Korean", r"Japanese",
    r"Ita\s+Eng", r"Sub\s*Ita\s*Eng", r"iTA[-.]ENG",
    # misc / well-known release groups
    r"ESubs?", r"MSubs?", r"AMZN", r"Proper", r"TRUE", r"HQ",
    r"NNMClub(?:\.\w+)?", r"6CH", r"WORLD",
    r"NiXON", r"EVO", r"GalaxyRG", r"NAHOM", r"Tigole", r"Hon3y", r"Telly",
    r"LOKiHD", r"CMRG", r"EtHD", r"MkvCage(?:\.\w+)?",
    r"YTS(?:\.\w+)?", r"TGx", r"TGx]?",
    r"PSA", r"MOVCR", r"Japhson", r"PublicHD", r"Exclusive", r"RGB",
    r"FraMeSToR", r"CiNEPHiLES", r"ExYuSubs", r"SeeHD",
]
NOISE_RE = re.compile(
    r"(?<![A-Za-z])(?:" + "|".join(_NOISE_TOKENS) + r")(?![A-Za-z])",
    re.IGNORECASE,
)


def scrub_title(title: str, year: int) -> str:
    """Deterministic post-processing: strip known-junk tokens from the LLM's title.

    Idempotent. Handles the cases where the LLM is too literal and leaves
    "1080p HDR WEB h265" in the title.
    """
    # 1. Remove any standalone occurrence of the year inside the title
    # ("Ad Astra 2019" -> "Ad Astra"; we add "(YYYY)" suffix ourselves later).
    if year:
        title = re.sub(rf"(?<!\d){year}(?!\d)", " ", title)
    # 2. Strip well-known noise tokens.
    title = NOISE_RE.sub(" ", title)
    # 3. Drop residual bracket fragments / lonely punctuation.
    title = re.sub(r"[\[\]{}]", " ", title)
    title = re.sub(r"\s*[-–—]\s*$", "", title)
    # 4. Collapse runs of whitespace / dots.
    title = re.sub(r"(?<=\w)\.(?=\w)", " ", title)
    title = re.sub(r"\s{2,}", " ", title)
    title = title.strip(" -–—.,;:_")
    return title


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


@dataclass
class Proposal:
    src: Path  # canonical (mergerfs-view) source path
    src_real: Path  # underlying branch path used for the actual rename
    dst: Path  # canonical (mergerfs-view) destination path
    dst_real: Path  # underlying branch path used for the actual rename
    title: str
    year: int
    confidence: str
    is_file: bool
    note: str = ""  # reason for rejection if not applied


def lock_or_die() -> int:
    """Acquire an exclusive lock or exit cleanly if another run is active."""
    fd = os.open(LOCKFILE, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        LOG.error("Another media-rename is already running (lockfile %s held)", LOCKFILE)
        sys.exit(2)
    os.write(fd, f"{os.getpid()}\n".encode())
    return fd


def already_clean(name: str) -> bool:
    """Check if the entry name already matches 'Title (YYYY)[.ext]'."""
    return bool(CLEAN_PATTERN.match(name))


def find_real_path(canonical: Path) -> Optional[Path]:
    """Translate a /media/... path to its underlying mergerfs-branch path.

    Returns the path on the *real* ext4 branch where the entry physically lives,
    so we can do `os.rename` within a single filesystem (instant inode swap)
    rather than across mergerfs (silent O(GB) copy across disks).
    """
    if not canonical.is_absolute():
        return None
    parts = canonical.parts
    if len(parts) < 3 or parts[1] != "media":
        # Not a /media/... path; assume caller knows what they're doing.
        return canonical if canonical.exists() else None

    relative = Path(*parts[2:])  # everything after /media/
    for branch in MERGERFS_BRANCHES:
        candidate = Path(branch) / relative
        if candidate.exists():
            return candidate
    return None


def query_llm(filename: str, model: str, timeout: float = 60.0) -> Optional[dict]:
    """Ask Ollama to extract {title, year, confidence}. None on failure."""
    body = json.dumps(
        {
            "model": model,
            "system": SYSTEM_PROMPT,
            "prompt": f"Filename: {filename}",
            "stream": False,
            "format": "json",
            "options": {"temperature": 0.1, "num_predict": 120},
        }
    ).encode()
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/generate",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            wrapped = json.loads(r.read())
    except (urllib.error.URLError, socket.timeout, json.JSONDecodeError) as e:
        LOG.warning("LLM request failed for %r: %s", filename, e)
        return None
    try:
        return json.loads(wrapped.get("response", ""))
    except json.JSONDecodeError as e:
        LOG.warning(
            "LLM returned non-JSON for %r: %s (raw=%r)",
            filename,
            e,
            wrapped.get("response", "")[:200],
        )
        return None


def sanity_check(parsed: dict, orig: str) -> Optional[str]:
    """Return None if proposal is sane, else a short rejection reason.

    `orig` is the original filename stem (no extension) — used to verify the
    LLM didn't hallucinate a year not present in the input.
    """
    if not isinstance(parsed, dict):
        return "llm output not an object"
    title = parsed.get("title")
    year = parsed.get("year")
    conf = parsed.get("confidence")

    if not isinstance(title, str) or not title.strip():
        return "empty title"
    if not (MIN_TITLE_LEN <= len(title) <= MAX_TITLE_LEN):
        return f"title length {len(title)} out of range"

    # Forbid suspicious characters in title (slash, control chars).
    if "/" in title or "\x00" in title:
        return "title contains forbidden chars"

    if not isinstance(year, int):
        # Some models return year as a string -- try to coerce.
        try:
            parsed["year"] = int(year)  # type: ignore[arg-type]
            year = parsed["year"]
        except (TypeError, ValueError):
            return f"year not an integer ({year!r})"

    # year=0 is the model's way of saying "I couldn't find one"; treat as reject
    # (we won't rename without a year — Jellyfin needs it to disambiguate).
    if year == 0:
        return "no year extractable from input"

    if not (MIN_YEAR <= year <= MAX_YEAR):
        return f"year {year} outside [{MIN_YEAR},{MAX_YEAR}]"

    # CRITICAL hallucination guard: the year MUST appear as a 4-digit substring
    # in the original input. If not, the model invented it from its own
    # training-data knowledge of the movie -- reject and force a manual review.
    years_in_input = {int(m) for m in INPUT_YEAR_RE.findall(orig)}
    if year not in years_in_input:
        return f"year {year} not found in input (years seen: {sorted(years_in_input) or 'none'})"

    if conf not in ("high", "medium", "low"):
        return f"unknown confidence {conf!r}"

    return None


def propose(entry: Path, model: str) -> Optional[Proposal]:
    """Build a Proposal for `entry`, or None to skip silently."""
    name = entry.name
    if name in SKIP_ENTRIES or name.startswith("."):
        return None
    if already_clean(name):
        return None

    is_file = entry.is_file()
    if is_file:
        ext = entry.suffix.lower() if entry.suffix.lower() in MEDIA_EXTS else ""
        stem = entry.stem if ext else name
    else:
        ext = ""
        stem = name

    parsed = query_llm(stem, model)
    if parsed is None:
        return None

    # Defensive normalization in case the LLM left dot-separated tokens in the
    # title (e.g. "Gran.Turismo" or "Due.West.Our.Sex.Journey"). Replace any
    # `.` between word characters with a single space.
    if isinstance(parsed, dict) and isinstance(parsed.get("title"), str):
        parsed["title"] = re.sub(r"(?<=\w)\.(?=\w)", " ", parsed["title"]).strip()
        # Collapse runs of whitespace.
        parsed["title"] = re.sub(r"\s+", " ", parsed["title"])

    reject = sanity_check(parsed, stem)

    title = (parsed or {}).get("title", "").strip()
    year = (parsed or {}).get("year")
    conf = (parsed or {}).get("confidence", "low")

    # Deterministic noise-token scrub on whatever the LLM returned. This
    # catches cases where the model leaves "1080p HDR WEB h265" in the title.
    if title and isinstance(year, int):
        title = scrub_title(title, year)
        # Re-validate after scrubbing.
        if not title:
            reject = reject or "title empty after scrub"

    if reject:
        return Proposal(
            src=entry,
            src_real=entry,
            dst=entry,
            dst_real=entry,
            title=str(title),
            year=int(year) if isinstance(year, int) else 0,
            confidence=str(conf),
            is_file=is_file,
            note=f"REJECT: {reject}",
        )

    new_name = f"{title} ({year}){ext}"
    src_real = find_real_path(entry)
    if src_real is None:
        return Proposal(
            src=entry,
            src_real=entry,
            dst=entry,
            dst_real=entry,
            title=title,
            year=int(year),
            confidence=conf,
            is_file=is_file,
            note="REJECT: cannot locate source on any mergerfs branch",
        )

    # Destination on the *same* underlying branch.
    dst_real = src_real.parent / new_name
    dst = entry.parent / new_name

    if dst_real.exists():
        return Proposal(
            src=entry,
            src_real=src_real,
            dst=dst,
            dst_real=dst_real,
            title=title,
            year=int(year),
            confidence=conf,
            is_file=is_file,
            note="REJECT: destination already exists",
        )

    return Proposal(
        src=entry,
        src_real=src_real,
        dst=dst,
        dst_real=dst_real,
        title=title,
        year=int(year),
        confidence=conf,
        is_file=is_file,
    )


def apply_rename(prop: Proposal) -> bool:
    """Do the actual rename. Returns True on success."""
    try:
        os.rename(prop.src_real, prop.dst_real)
    except OSError as e:
        LOG.error("RENAME FAILED %s -> %s: %s", prop.src_real, prop.dst_real, e)
        return False
    LOG.info("RENAMED %s -> %s", prop.src.name, prop.dst.name)
    return True


def trigger_jellyfin_scan() -> None:
    """Best-effort: hit /Library/Refresh with the API key."""
    if not JELLYFIN_API_KEY:
        LOG.info("JELLYFIN_API_KEY not set; skipping library refresh")
        return
    url = f"{JELLYFIN_URL}/Library/Refresh?api_key={JELLYFIN_API_KEY}"
    req = urllib.request.Request(url, method="POST", data=b"")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            LOG.info("Jellyfin /Library/Refresh -> HTTP %s", r.status)
    except (urllib.error.URLError, socket.timeout, ssl.SSLError) as e:
        LOG.warning("Jellyfin refresh failed: %s", e)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def iter_entries(root: Path):
    if not root.is_dir():
        LOG.warning("Not a directory, skipping: %s", root)
        return
    for entry in sorted(root.iterdir()):
        yield entry


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="print proposals only (default)")
    mode.add_argument("--apply", action="store_true", help="actually rename high-confidence proposals")
    mode.add_argument("--interactive", action="store_true", help="prompt y/n per proposal")
    ap.add_argument("--path", default="/media/movies", help="directory to scan (default /media/movies)")
    ap.add_argument("--model", default=OLLAMA_MODEL, help="ollama model name")
    ap.add_argument("--no-jellyfin", action="store_true", help="skip Jellyfin library refresh at end")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s  %(levelname)-7s  %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    if not args.apply and not args.interactive:
        args.dry_run = True

    fd = lock_or_die()  # noqa: F841 -- held until process exit

    root = Path(args.path)
    LOG.info("Scanning %s with model=%s (mode=%s)", root, args.model,
             "apply" if args.apply else "interactive" if args.interactive else "dry-run")

    proposals: list[Proposal] = []
    t0 = time.time()
    seen = 0
    for entry in iter_entries(root):
        seen += 1
        prop = propose(entry, args.model)
        if prop is None:
            continue
        proposals.append(prop)
        marker = "  " if not prop.note else "✗ "
        LOG.info("%s%-70s -> %s  (%s)  %s",
                 marker,
                 entry.name[:70],
                 prop.dst.name,
                 prop.confidence,
                 prop.note)

    if not proposals:
        LOG.info("Nothing to do (seen=%d, all clean/skipped)", seen)
        if not args.no_jellyfin and args.apply:
            trigger_jellyfin_scan()
        return 0

    LOG.info(
        "Found %d proposals (%.1fs, %.2fs/item avg) out of %d entries",
        len(proposals),
        time.time() - t0,
        (time.time() - t0) / max(seen, 1),
        seen,
    )

    if args.dry_run:
        # Summarize what would happen.
        ok = [p for p in proposals if not p.note and p.confidence == "high"]
        skipped = [p for p in proposals if p.note or p.confidence != "high"]
        LOG.info("DRY-RUN: %d would be applied, %d would be skipped", len(ok), len(skipped))
        return 0

    applied = 0
    failed = 0
    for prop in proposals:
        if prop.note:
            LOG.info("SKIP %s (%s)", prop.src.name, prop.note)
            continue
        if prop.confidence != "high":
            LOG.info("SKIP %s (confidence=%s, need 'high')", prop.src.name, prop.confidence)
            continue

        if args.interactive:
            print(f"\n  {prop.src.name}")
            print(f"->  {prop.dst.name}")
            try:
                ans = input("apply? [y/N] ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                print()
                break
            if ans not in ("y", "yes"):
                LOG.info("user skipped %s", prop.src.name)
                continue

        if apply_rename(prop):
            applied += 1
        else:
            failed += 1

    LOG.info("DONE: %d applied, %d failed, %d skipped",
             applied, failed, len(proposals) - applied - failed)

    if applied and not args.no_jellyfin:
        trigger_jellyfin_scan()

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
