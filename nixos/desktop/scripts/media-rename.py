#!/usr/bin/env python3
"""media-rename.py – Clean torrent-style filenames under /media.

Strips website prefixes (TamilRockers, TamilBlasters, …), quality tags
(1080p, HDRip, x264, …), release-group suffixes, and bracket noise,
leaving behind clean names like:

    Title (Year).ext   or   Title (Year)/

Usage:
    python3 media-rename.py            # perform renames
    python3 media-rename.py --dry-run  # preview only (no disk changes)
"""

import os
import re
import sys
import logging
from pathlib import Path

# ── Configuration ──────────────────────────────────────────────────────────

MEDIA_ROOTS = [
    "/media",
    "/media/downloads",
    "/media/downloads/radarr",
]

# Top-level entries to never touch (exact match, case-sensitive)
SKIP_ENTRIES = {
    ".incomplete", "downloads", "transmission", "radarr",
    "lost+found", "sonarr", ".Trash-1000",
}

# ── Regex patterns ─────────────────────────────────────────────────────────

# Website prefixes:  www.TamilRockers.ws -   www.1TamilMV.pink -   etc.
SITE_PREFIX_RE = re.compile(
    r"^(?:www\.)?(?:\d?)"
    r"(?:Tamil(?:Rocke?rs|Blasters|MV)"
    r"|Torrenting|UIndex|Movcr|MkvCage|TorrentCounter)"
    r"(?:\.\w+)+"
    r"\s*[-–—]\s*",
    re.IGNORECASE,
)

# Leading [site.tld] or [site.tld]. prefix
BRACKET_SITE_RE = re.compile(
    r"^\[(?:www\.)?[\w.-]+\.\w{2,5}\]\s*\.?\s*[-–—]?\s*",
    re.IGNORECASE,
)

# Parenthesised group containing quality/encoding tokens (but NOT year-only)
PAREN_QUALITY_RE = re.compile(
    r"\("
    r"(?!\d{4}\))"                          # not a bare (YYYY)
    r"[^)]*?"
    r"(?:\d{3,4}p|HDRip|WEBRip|WEB[-.]?DL|BluRay|BDR(?:ip|emux)|DVDRip|"
    r"[xX]\.?26[45]|HEVC|AVC|HDR|UHD|Atmos|TrueHD|DTS|DD[P+]?\d)"
    r"[^)]*"
    r"\)",
    re.IGNORECASE,
)

# Parenthesised website – (eurocoalition.org)
PAREN_SITE_RE = re.compile(
    r"\([\w.-]+\.(?:org|com|net|tv|ws|co|top|mov|tel|pink|rsvp)\)",
    re.IGNORECASE,
)

# Quality / encoding tokens (matched as whole "words")
_Q_TOKENS = [
    # resolution
    r"\d{3,4}p", r"4K", r"UHD",
    # source
    r"HDRip", r"WEBRip", r"WEB[-.]?DL", r"BluRay", r"BDRemux", r"BDREMUX",
    r"DVDRip", r"DvDRip", r"BDRip", r"HDTV",
    # HDR
    r"HDR\d*P?", r"SDR", r"DV\b",
    # codec
    r"[xX]\.?26[45]", r"H\.?26[45]", r"HEVC", r"AVC", r"XviD",
    r"10\s?[Bb]it",
    # audio
    r"DD[P+]?\s*\d\.\d", r"DD\s*\d\.\d", r"AC3", r"AAC", r"FLAC",
    r"DTS(?:[-.](?:HD|X|MA))?\s*(?:\d\.\d)?",
    r"TrueHD", r"Atmos",
    r"\d\.\d(?:\s*CH)?",     # 5.1, 7.1, 2.0
    r"\d{2,3}\s?[Kk]bps",
    # size
    r"\d+(?:\.\d+)?\s*[GMK]B",
    # languages (full names only – abbreviations are too risky)
    r"Hindi", r"Tamil", r"Telugu", r"Malayalam", r"Kannada",
    r"English", r"Korean", r"Japanese",
    r"Ita\s+Eng", r"Sub\s*Ita\s*Eng",
    r"iTA[-.]ENG",
    # misc
    r"UNTOUCHED", r"REPACK", r"UNRATED",
    r"ESubs?", r"MSubs?",
    r"AMZN",
    r"NNMClub(?:\.\w+)?",
    r"6CH",
]
QUALITY_RE = re.compile(
    r"(?<![A-Za-z])(?:" + "|".join(_Q_TOKENS) + r")(?![A-Za-z])",
    re.IGNORECASE,
)

# Release group at end:  -NAHOM, -EVO[TGx], - Telly, etc.
RELEASE_GROUP_RE = re.compile(
    r"\s*[-–]\s*[A-Za-z0-9][\w.]*(?:\s*\[[\w.]+\])?\s*$"
)

# Year (1920 – 2029) with context-aware boundaries
YEAR_RE = re.compile(
    r"(?:^|[\s.([_-])((?:19|20)\d{2})(?=[\s.)\]_,-]|$)"
)

# Season / episode:  S01  S01E03  S02E01-E10  etc.
SEASON_RE = re.compile(
    r"(S\d{1,2}(?:E\d{1,2}(?:-E?\d{1,2})?)?)",
    re.IGNORECASE,
)

# Known media file extensions
MEDIA_EXTS = {
    ".mkv", ".mp4", ".avi", ".m4v", ".mov", ".wmv", ".flv", ".webm",
    ".srt", ".sub", ".idx", ".ass", ".ssa",
    ".nfo", ".txt", ".jpg", ".jpeg", ".png",
}

# Quick indicators that a filename needs cleaning
INDICATORS = [
    "tamilrocker", "tamilblaster", "tamilmv", "torrentcounter",
    "torrenting.com", "uindex.org", "movcr", "mkvcage",
    "[yts", "[tgx", "[ethd", "[rick", "[publichd", "[movcr",
    "[exclusive", "[mp4",
    "hdrip", "webrip", "web-dl", "bluray", "bdrip", "bdremux",
    "dvdrip", "hdtv",
    "x264", "x265", "h264", "h.264", "hevc", "avc", "xvid",
    "1080p", "720p", "2160p",
    "www.", "[www.",
    "- hon3y", "- telly", "-evo", "-psa", "-cmrg",
    "galaxyrg", "nnmclub", "seehd",
    "tigole", "r00t", "nahom",
]


# ── Core logic ─────────────────────────────────────────────────────────────

def should_process(name: str) -> bool:
    """Return True if the name looks like it needs cleaning."""
    low = name.lower()
    return any(tag in low for tag in INDICATORS)


def _strip_brackets(name: str) -> str:
    """Iteratively remove all [...] groups (handles nesting)."""
    prev = None
    while prev != name:
        prev = name
        name = re.sub(r"\[[^\[\]]*\]", " ", name)
    return name


def clean_name(raw: str, is_file: bool = True) -> str:
    """Return a cleaned version of *raw*.  Preserves extension for files."""

    # ── Separate extension ──────────────────────────────────────────────
    ext = ""
    if is_file:
        p = Path(raw)
        if p.suffix.lower() in MEDIA_EXTS:
            ext = p.suffix
            name = raw[: -len(ext)]
        else:
            name = raw
    else:
        name = raw

    # ── 1. Strip site prefixes ──────────────────────────────────────────
    name = SITE_PREFIX_RE.sub("", name)
    name = BRACKET_SITE_RE.sub("", name)

    # ── 2. Strip all [...] bracket content ──────────────────────────────
    name = _strip_brackets(name)

    # ── 3. Dots → spaces (between word characters) ─────────────────────
    name = re.sub(r"(?<=\w)\.(?=\w)", " ", name)
    name = name.strip(". ")

    # ── 4. Find year ────────────────────────────────────────────────────
    year = None
    title = None
    after_year = ""

    for m in YEAR_RE.finditer(name):
        y = m.group(1)
        candidate = name[: m.start(1)].strip(" (-–—.")
        if len(candidate) >= 1:          # title must be non-empty
            year = y
            title = candidate
            after_year = name[m.end(1):]
            break

    # ── 5. Build result ─────────────────────────────────────────────────
    if year and title:
        # Remove stray quality tokens that leaked into the title
        title = QUALITY_RE.sub(" ", title)
        title = re.sub(r"[(){}\[\]]", " ", title)
        title = re.sub(r"\s{2,}", " ", title)
        title = title.strip(" -–—.,;:")

        # Preserve season/episode info after the year
        season = ""
        if after_year:
            sm = SEASON_RE.search(after_year)
            if sm:
                season = " " + sm.group(1).upper()

        if not title:
            return raw                    # safety: don't rename to empty
        result = f"{title} ({year}){season}{ext}"
    else:
        # No year found – strip quality parens, then cut at first token
        name = PAREN_QUALITY_RE.sub(" ", name)
        name = PAREN_SITE_RE.sub(" ", name)
        name = re.sub(r"\s{2,}", " ", name).strip()

        qm = QUALITY_RE.search(name)
        if qm:
            title = name[: qm.start()]
        else:
            title = name

        title = RELEASE_GROUP_RE.sub("", title)
        title = re.sub(r"[(){}\[\]]", " ", title)
        title = re.sub(r"\s{2,}", " ", title)
        title = title.strip(" -–—.,;:")

        if not title:
            return raw
        result = f"{title}{ext}"

    return result


# ── File-system operations ─────────────────────────────────────────────────

def _rename(old: str, new: str, dry_run: bool) -> bool:
    """Rename *old* → *new*.  Returns True on success."""
    if os.path.exists(new):
        logging.warning("SKIP (target exists): %s\n  -> %s", old, new)
        return False
    logging.info("RENAME: %s\n     -> %s", old, new)
    if not dry_run:
        try:
            os.rename(old, new)
        except OSError as exc:
            logging.error("FAILED: %s – %s", old, exc)
            return False
    return True


def process_inner_files(directory: str, dry_run: bool):
    """Rename media files *inside* a movie/show folder."""
    if not os.path.isdir(directory):
        return
    for fname in sorted(os.listdir(directory)):
        if fname.startswith("."):
            continue
        fpath = os.path.join(directory, fname)
        if os.path.isdir(fpath):
            process_inner_files(fpath, dry_run)     # recurse one level
            continue
        if not os.path.isfile(fpath):
            continue
        if not should_process(fname):
            continue
        new_name = clean_name(fname, is_file=True)
        if new_name == fname:
            continue
        _rename(fpath, os.path.join(directory, new_name), dry_run)


def process_directory(base: str, dry_run: bool):
    """Rename entries directly under *base* and clean files inside them."""
    if not os.path.isdir(base):
        logging.warning("Not a directory, skipping: %s", base)
        return

    for entry in sorted(os.listdir(base)):
        if entry in SKIP_ENTRIES or entry.startswith("."):
            continue

        full = os.path.join(base, entry)
        is_dir = os.path.isdir(full)
        is_file = os.path.isfile(full)

        if should_process(entry):
            new_name = clean_name(entry, is_file=is_file)
            if new_name != entry:
                new_full = os.path.join(base, new_name)
                if _rename(full, new_full, dry_run):
                    full = new_full if not dry_run else full

        # Recurse into directories to clean inner files
        if os.path.isdir(full):
            process_inner_files(full, dry_run)


# ── Entry point ────────────────────────────────────────────────────────────

def main():
    dry_run = "--dry-run" in sys.argv
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s  %(levelname)-7s  %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    if dry_run:
        logging.info(">>> DRY RUN – no files will be renamed <<<")

    for root in MEDIA_ROOTS:
        logging.info("── Scanning: %s ──", root)
        process_directory(root, dry_run)

    logging.info("── Done ──")


if __name__ == "__main__":
    main()
