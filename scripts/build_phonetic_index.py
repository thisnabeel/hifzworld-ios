#!/usr/bin/env python3
"""
Build unzyla/Resources/phonetic-ayahs.json for offline phonetic verse search.

For each mushaf, every verse and every surah gets an exact page range:

  Mushaf 2 (IndoPak 13-line, 847 pages):
    scrape ayah tags from qiraat-api pages (no interpolation)

  Mushaf 3 (Uthmani 15-line, 604 pages):
    Quran.com verse page_number (qiraat-api mushaf 3 has no ayah tags)

Surah ranges are the min/max page of that surah's verses on that mushaf.
segments.json surah (and Uthmani juz/surah) entries are rewritten from the same maps.

Usage:
  python3 scripts/build_phonetic_index.py
"""

from __future__ import annotations

import concurrent.futures
import json
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "unzyla" / "Resources" / "phonetic-ayahs.json"
SEGMENTS = ROOT / "unzyla" / "Resources" / "segments.json"
TRANSLIT_URL = "https://cdn.jsdelivr.net/npm/quran-json@3.1.2/dist/quran_transliteration.json"
QURAN_COM = "https://api.quran.com/api/v4"
API_BASE = "https://qiraat-api-v2-production.up.railway.app"

INDOPAK_MUSHAF = 2
UTHMANI_MUSHAF = 3
INDOPAK_PAGES = 847
UTHMANI_PAGES = 604
WORKERS = 8

AYAH_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
    54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
    14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
    29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
    11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
]

# Standard 15-line Madinah juz page ranges (inclusive).
UTHMANI_JUZ = [
    (1, 1, 20), (2, 21, 39), (3, 40, 59), (4, 60, 79), (5, 80, 99),
    (6, 100, 119), (7, 120, 139), (8, 140, 159), (9, 160, 177), (10, 178, 201),
    (11, 202, 221), (12, 222, 241), (13, 242, 261), (14, 262, 281), (15, 282, 301),
    (16, 302, 321), (17, 322, 341), (18, 342, 361), (19, 362, 381), (20, 382, 401),
    (21, 402, 421), (22, 422, 441), (23, 442, 461), (24, 462, 481), (25, 482, 501),
    (26, 502, 521), (27, 522, 541), (28, 542, 561), (29, 562, 581), (30, 582, 604),
]


def fetch_json(url: str, retries: int = 5, timeout: int = 60):
    last_exc: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "unzyla-phonetic-index/1.1"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.load(resp)
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            time.sleep(0.4 * (attempt + 1))
    raise last_exc  # type: ignore[misc]


def expected_verse_keys() -> list[str]:
    keys: list[str] = []
    for surah, count in enumerate(AYAH_COUNTS, start=1):
        for ayah in range(1, count + 1):
            keys.append(f"{surah}:{ayah}")
    return keys


def madani_page_map() -> dict[str, int]:
    pages: dict[str, int] = {}
    for chapter in range(1, 115):
        url = (
            f"{QURAN_COM}/verses/by_chapter/{chapter}"
            f"?fields=verse_key,page_number&per_page=300"
        )
        data = fetch_json(url)
        for verse in data.get("verses") or []:
            pages[verse["verse_key"]] = int(verse["page_number"])
        print(f"  uthmani chapter {chapter}/114")
    return pages


def page_ayahs(mushaf_id: int, position: int) -> tuple[int, list[str] | None]:
    url = f"{API_BASE}/api/mushafs/{mushaf_id}/pages/{position}"
    try:
        data = fetch_json(url)
    except Exception as exc:  # noqa: BLE001
        print(f"warn mushaf {mushaf_id} page {position}: {exc}", file=sys.stderr)
        return position, None

    keys: list[str] = []
    for line in data.get("lines") or []:
        for word in line.get("words") or []:
            ayah = word.get("ayah")
            if isinstance(ayah, str) and ":" in ayah and not ayah.startswith("p"):
                keys.append(ayah)
    return position, keys


def best_verse_page(counts: dict[int, int]) -> int:
    """Dominant page, ignoring sparse mis-tags on distant pages."""
    if not counts:
        raise ValueError("empty counts")
    peak = max(counts.values())
    floor = max(3, int(round(peak * 0.15)))
    eligible = {page: count for page, count in counts.items() if count >= floor}
    if not eligible:
        eligible = counts
    return min(eligible.items(), key=lambda item: (-item[1], item[0]))[0]


def scrape_verse_pages(mushaf_id: int, total_pages: int) -> dict[str, int]:
    """Page for each verse: the page with the most tagged words (tie → earliest page)."""
    word_counts: dict[str, dict[int, int]] = {}
    failed: list[int] = []
    positions = list(range(1, total_pages + 1))
    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = [pool.submit(page_ayahs, mushaf_id, p) for p in positions]
        for fut in concurrent.futures.as_completed(futures):
            position, keys = fut.result()
            if keys is None:
                failed.append(position)
            else:
                for key in keys:
                    word_counts.setdefault(key, {})
                    word_counts[key][position] = word_counts[key].get(position, 0) + 1
            done += 1
            if done % 100 == 0 or done == total_pages:
                print(f"  mushaf {mushaf_id}: {done}/{total_pages} ({len(failed)} failed)")

    for attempt in range(1, 6):
        if not failed:
            break
        print(f"  retrying {len(failed)} failed pages (pass {attempt})")
        still: list[int] = []
        for position in sorted(failed):
            pos, keys = page_ayahs(mushaf_id, position)
            if keys is None:
                still.append(pos)
                continue
            for key in keys:
                word_counts.setdefault(key, {})
                word_counts[key][pos] = word_counts[key].get(pos, 0) + 1
        failed = still

    if failed:
        print(f"  still failed after retries: {failed[:20]}{'…' if len(failed) > 20 else ''}", file=sys.stderr)

    verse_pages: dict[str, int] = {}
    for key, counts in word_counts.items():
        verse_pages[key] = best_verse_page(counts)
    return verse_pages


def fill_missing_from_neighbors(pages: dict[str, int], label: str) -> dict[str, int]:
    """Fill untagged verses from the previous ayah's page (monotonic, not interpolated)."""
    filled = dict(pages)
    missing_before = 0
    last_page: int | None = None
    for key in expected_verse_keys():
        if key in filled:
            last_page = filled[key]
            continue
        missing_before += 1
        if last_page is not None:
            filled[key] = last_page
    still = [k for k in expected_verse_keys() if k not in filled]
    print(f"  {label}: tagged={len(pages)} filled_from_neighbor={missing_before} still_missing={len(still)}")
    return filled


def surah_ranges(verse_pages: dict[str, int]) -> dict[int, tuple[int, int]]:
    """First ayah page → last ayah page per surah (robust against stray tags)."""
    ranges: dict[int, tuple[int, int]] = {}
    for surah, count in enumerate(AYAH_COUNTS, start=1):
        first_key = f"{surah}:1"
        last_key = f"{surah}:{count}"
        if first_key not in verse_pages or last_key not in verse_pages:
            continue
        start = verse_pages[first_key]
        end = verse_pages[last_key]
        ranges[surah] = (min(start, end), max(start, end))
    return ranges


def surah_titles_from_segments(data: list[dict]) -> dict[int, str]:
    titles: dict[int, str] = {}
    for entry in data:
        fields = entry.get("fields") or {}
        if fields.get("mushaf") == INDOPAK_MUSHAF and fields.get("category") == "surah":
            titles[int(fields["category_position"])] = fields["title"]
    return titles


def update_segments_json(
    p2_surah: dict[int, tuple[int, int]],
    p3_surah: dict[int, tuple[int, int]],
) -> None:
    data = json.loads(SEGMENTS.read_text(encoding="utf-8"))
    titles = surah_titles_from_segments(data)
    next_pk = max(int(entry.get("pk") or 0) for entry in data) + 1

    updated = 0
    for entry in data:
        fields = entry.get("fields") or {}
        if fields.get("mushaf") != INDOPAK_MUSHAF or fields.get("category") != "surah":
            continue
        surah = int(fields["category_position"])
        if surah not in p2_surah:
            continue
        first, last = p2_surah[surah]
        if fields.get("first_page") != first or fields.get("last_page") != last:
            fields["first_page"] = first
            fields["last_page"] = last
            updated += 1

    has_uthmani = any((e.get("fields") or {}).get("mushaf") == UTHMANI_MUSHAF for e in data)
    if not has_uthmani:
        for juz, first, last in UTHMANI_JUZ:
            data.append(
                {
                    "model": "mushaf_segment.mushafsegment",
                    "pk": next_pk,
                    "fields": {
                        "first_page": first,
                        "last_page": last,
                        "title": f"Juz {juz}",
                        "mushaf": UTHMANI_MUSHAF,
                        "category": "juz",
                        "category_position": juz,
                    },
                }
            )
            next_pk += 1
        for surah in range(1, 115):
            first, last = p3_surah[surah]
            data.append(
                {
                    "model": "mushaf_segment.mushafsegment",
                    "pk": next_pk,
                    "fields": {
                        "first_page": first,
                        "last_page": last,
                        "title": titles.get(surah, f"Surah {surah}"),
                        "mushaf": UTHMANI_MUSHAF,
                        "category": "surah",
                        "category_position": surah,
                    },
                }
            )
            next_pk += 1
        print(f"  added mushaf 3 juz+surah segments")
    else:
        for entry in data:
            fields = entry.get("fields") or {}
            if fields.get("mushaf") != UTHMANI_MUSHAF or fields.get("category") != "surah":
                continue
            surah = int(fields["category_position"])
            if surah not in p3_surah:
                continue
            first, last = p3_surah[surah]
            if fields.get("first_page") != first or fields.get("last_page") != last:
                fields["first_page"] = first
                fields["last_page"] = last
                updated += 1
            arabic = titles.get(surah)
            if arabic and fields.get("title") != arabic and str(fields.get("title", "")).startswith("Surah "):
                fields["title"] = arabic
                updated += 1

    SEGMENTS.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"  updated {updated} existing surah page ranges in segments.json")


def main() -> None:
    print("Downloading Tanzil transliteration…")
    surahs = fetch_json(TRANSLIT_URL)
    ayah_rows: list[dict] = []
    for surah in surahs:
        sid = surah["id"]
        for verse in surah["verses"]:
            ayah_rows.append(
                {
                    "k": f"{sid}:{verse['id']}",
                    "t": verse["transliteration"],
                    "a": verse["text"],
                }
            )
    print(f"  {len(ayah_rows)} ayahs")

    print("Fetching Uthmani (mushaf 3) verse pages from Quran.com…")
    p3_map = fill_missing_from_neighbors(madani_page_map(), "p3")

    print("Scraping IndoPak (mushaf 2) verse pages from qiraat-api…")
    p2_raw = scrape_verse_pages(INDOPAK_MUSHAF, INDOPAK_PAGES)
    p2_map = fill_missing_from_neighbors(p2_raw, "p2")

    expected = expected_verse_keys()
    missing2 = [k for k in expected if k not in p2_map]
    missing3 = [k for k in expected if k not in p3_map]
    if missing2 or missing3:
        raise SystemExit(f"Incomplete maps: p2 missing {len(missing2)}, p3 missing {len(missing3)}")

    p2_surah = surah_ranges(p2_map)
    p3_surah = surah_ranges(p3_map)
    if len(p2_surah) != 114 or len(p3_surah) != 114:
        raise SystemExit(f"Surah coverage p2={len(p2_surah)} p3={len(p3_surah)}")

    rows = []
    for row in ayah_rows:
        key = row["k"]
        rows.append({"k": key, "t": row["t"], "a": row["a"], "p2": p2_map[key], "p3": p3_map[key]})

    surah_rows = []
    for n in range(1, 115):
        s2 = p2_surah[n]
        s3 = p3_surah[n]
        surah_rows.append({"n": n, "p2": [s2[0], s2[1]], "p3": [s3[0], s3[1]]})

    payload = {
        "_meta": {
            "description": "Phonetic ayah search index for Hifz.World",
            "transliteration": "Tanzil en.transliteration via quran-json (CC BY)",
            "p3": "Quran.com Madani page_number for every verse (15-line / mushaf 3)",
            "p2": "qiraat-api mushaf 2 ayah tags — dominant page per verse (13-line IndoPak)",
            "surahs": "min/max verse page per surah for each mushaf",
        },
        "surahs": surah_rows,
        "ayahs": rows,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")

    print("Updating segments.json from verse maps…")
    update_segments_json(p2_surah, p3_surah)

    sample = next(r for r in rows if r["k"] == "2:185")
    print("2:185:", sample)
    print("surah 2:", next(s for s in surah_rows if s["n"] == 2))
    print(f"Coverage: verses={len(rows)} surahs={len(surah_rows)} p2={len(p2_map)} p3={len(p3_map)}")


if __name__ == "__main__":
    main()
