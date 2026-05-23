#!/usr/bin/env bash
# Fetch small canonical public test files into corpus_public/<format>/<source>/.
#
# Each entry: URL + destination path + provenance note.
# All files committed; SOURCES.md tracks provenance + license.
#
# Sources used (all permissive license or public domain):
#   - PngSuite by Willem van Schaik (PNG test images, used by W3C; public domain)
#       http://www.schaik.com/pngsuite/pngsuite.html
#   - libpng test directory on GitHub (zlib license)
#       https://github.com/glennrp/libpng/tree/libpng16/contrib/pngsuite
#   - Mozilla pdf.js test corpus (Apache 2.0)
#       https://github.com/mozilla/pdf.js/tree/master/test/pdfs
#   - libjxl test images (Apache 2.0)
#       https://github.com/libjxl/testdata
#   - ffmpeg FATE samples (various permissive licenses)
#       https://samples.ffmpeg.org/
#   - libtiff test images (libtiff/BSD-style)
#       https://gitlab.com/libtiff/libtiff/-/tree/master/test/images
#   - GIPHY / Wikimedia: avoided (rate-limits / lawyer-fear).
#
# Files are size-capped at 1 MB each (audit speed + repo size). Larger files
# are skipped with a log entry.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CORPUS="$AUDIT_DIR/corpus_public"
LOG="$AUDIT_DIR/results/public-fetch.log"
SIZE_CAP=$((1024 * 1024))   # 1 MB

mkdir -p "$CORPUS" "$AUDIT_DIR/results"
: > "$LOG"

have() { command -v "$1" >/dev/null 2>&1; }
have curl || { echo "FATAL: curl required"; exit 1; }

# fetch <url> <dest_subpath> <provenance_note>
fetch() {
    local url="$1"
    local subpath="$2"
    local note="$3"
    local dest="$CORPUS/$subpath"

    if [[ -f "$dest" ]]; then
        echo "  SKIP (exists): $subpath" >> "$LOG"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    local tmp; tmp=$(mktemp)
    if ! curl -fsSL --max-time 30 "$url" -o "$tmp" 2>/dev/null; then
        echo "  FAIL (download): $url" >> "$LOG"
        rm -f "$tmp"
        return 1
    fi
    local size; size=$(stat -f%z "$tmp" 2>/dev/null || stat -c%s "$tmp" 2>/dev/null)
    if [[ "$size" -gt "$SIZE_CAP" ]]; then
        echo "  SKIP (too large, ${size} B): $url" >> "$LOG"
        rm -f "$tmp"
        return 0
    fi
    mv "$tmp" "$dest"
    echo "  OK ($size B): $subpath — $note" >> "$LOG"
    echo "    $subpath ($size B)"
}

echo "Fetching public test files into $CORPUS/..."
echo

# ─── PngSuite via libpng's GitHub mirror (zlib license) ──────────────────
# The canonical schaik.com URLs return 404s as of 2026-05 (site restructured),
# but the libpng project bundles the full PngSuite in their repo. The files
# are byte-identical to Willem van Schaik's originals — the libpng folks just
# vendored them. zlib license.
echo "PNG: PngSuite via libpng16/contrib/pngsuite (zlib license)"
LIBPNG_BASE="https://raw.githubusercontent.com/pnggroup/libpng/libpng16/contrib/pngsuite"
# libpng's contrib/pngsuite vendors only the "basn" (non-interlaced) suite
# plus the "ftb" test-bed variants. The interlaced basi* / s* / pp* / etc.
# series live in the canonical PngSuite distribution which doesn't have a
# stable script-fetchable URL right now. We pick a representative subset
# from what libpng actually mirrors.
for fn in \
    basn0g01.png basn0g02.png basn0g04.png basn0g08.png basn0g16.png \
    basn2c08.png basn2c16.png \
    basn3p01.png basn3p02.png basn3p04.png basn3p08.png \
    basn4a08.png basn4a16.png \
    basn6a08.png basn6a16.png \
    ftbbn0g01.png ftbbn0g02.png ftbbn0g04.png \
    ; do
    fetch "$LIBPNG_BASE/$fn" "png/pngsuite/$fn" "PngSuite by Willem van Schaik, vendored in libpng16"
done

# ─── Mozilla pdf.js test PDFs (Apache 2.0) ───────────────────────────────
echo
echo "PDF: Mozilla pdf.js test corpus (Apache 2.0)"
PDFJS_BASE="https://raw.githubusercontent.com/mozilla/pdf.js/master/test/pdfs"
# A varied subset of confirmed-existing files from mozilla/pdf.js@master as
# of 2026-05. Some of these test PDFs are intentionally weird/quirky/broken-
# but-tolerated, which makes them excellent stress inputs for blar's PDF
# round-trip path.
for fn in \
    issue2840.pdf issue3061.pdf issue3371.pdf issue8061.pdf issue9252.pdf \
    bug1250079.pdf \
    ; do
    fetch "$PDFJS_BASE/$fn" "pdf/mozilla-pdfjs/$fn" "Mozilla pdf.js test corpus"
done

# ─── libjxl test images — skipped (no reliably-fetchable direct URLs) ───
# libjxl's testdata repo files are accessible only via git clone, not raw URLs.
# Rely on PngSuite + synthetic for image-format diversity.

# ─── ffmpeg FATE wav/aiff samples ────────────────────────────────────────
# ffmpeg samples server has CC-BY-style licenses; tiny sine waves are fine
# to redistribute. Using stable URLs.
echo
echo "WAV/AIFF: ffmpeg FATE samples (permissive)"
# Use small ones; ffmpeg samples server has redirect that may be flaky — skip if no response.
FATE_BASE="https://samples.ffmpeg.org/A-codecs/PCM"
# (Many of these are several MB; rely on synthetic + local instead. Keeping as a hook.)
echo "  (no curated list yet — ffmpeg FATE samples typically exceed 1 MB; relying on synthetic + local for audio.)" >> "$LOG"

# ─── libtiff test images (BSD-style) ─────────────────────────────────────
echo
echo "TIFF: libtiff test images (BSD-style)"
LIBTIFF_BASE="https://gitlab.com/libtiff/libtiff/-/raw/master/test/images"
for fn in \
    minisblack-1c-8b.tiff minisblack-1c-16b.tiff \
    miniswhite-1c-1b.tiff \
    rgb-3c-8b.tiff rgb-3c-16b.tiff \
    palette-1c-8b.tiff \
    ; do
    fetch "$LIBTIFF_BASE/$fn" "tiff/libtiff/$fn" "libtiff master test/images"
done

# ─── Wikipedia: small permissively-licensed BMPs / TGAs / GIFs ───────────
# Skipping for now — Wikipedia per-image licensing varies and downloading
# from Wikimedia in bulk is rate-limited / requires User-Agent dance.

# ─── EPUB: project Gutenberg samples ─────────────────────────────────────
# Gutenberg's robots.txt actively discourages scripted bulk fetching.
# Curate one or two well-known small public-domain titles via manual URL.
echo
echo "EPUB: Project Gutenberg (public domain, small sample)"
fetch "https://www.gutenberg.org/ebooks/74.epub.images" "epub/gutenberg/tom_sawyer.epub" "Project Gutenberg: Tom Sawyer (#74)"
fetch "https://www.gutenberg.org/ebooks/1342.epub.images" "epub/gutenberg/pride_and_prejudice.epub" "Project Gutenberg: Pride and Prejudice (#1342)"

# ─── Summary ─────────────────────────────────────────────────────────────
echo
echo "=== Fetch complete ==="
echo "Total files in $CORPUS:"
find "$CORPUS" -type f | wc -l
echo "(See $LOG for per-file detail)"

# ─── SOURCES.md regen ────────────────────────────────────────────────────
cat > "$CORPUS/SOURCES.md" <<'EOF'
# Public Corpus Sources

Each entry below lists the provenance and license of a subdirectory's contents.
All files in `corpus_public/` are either synthetically generated (no license issue) or fetched from sources with permissive licenses compatible with public redistribution.

## Synthetic (generated by `scripts/gen_synthetic.sh`)

Subdirs named after the tool that produced them:
- `*/imagemagick/` — ImageMagick `convert` (Apache 2.0-ish "ImageMagick license")
- `*/ghostscript/` — Ghostscript (AGPL when used for distribution; we generate test files only — no Ghostscript code is distributed in our binaries)
- `*/pandoc/` — pandoc (GPL when used; same caveat)
- `*/pdflatex/` — TeX Live (LPPL)
- `*/ffmpeg/` — FFmpeg (LGPL/GPL)
- `*/libflac/` — FLAC reference encoder (BSD)
- `*/sox/` — SoX (LGPL/GPL)
- `*/info-zip/` — Info-ZIP (Info-ZIP license, very permissive)
- `*/p7zip/` — p7zip (LGPL)
- `*/gnu_gzip/` — GNU gzip (GPL)
- `*/pigz/` — pigz (zlib-style)
- `*/pngquant/`, `*/oxipng/`, `*/optipng/` — re-encoders (GPL / MIT)

## Publicly-fetched

| Subdir | Source | License |
|---|---|---|
| `png/pngsuite/` | PngSuite 2017-07-19 by Willem van Schaik (http://www.schaik.com/pngsuite/) | Public domain |
| `png/libpng/` | libpng `contrib/pngsuite` directory | zlib license |
| `pdf/mozilla-pdfjs/` | Mozilla pdf.js `test/pdfs/` | Apache 2.0 |
| `tiff/libtiff/` | libtiff `test/images/` | libtiff (BSD-style) |
| `epub/gutenberg/` | Project Gutenberg curated samples | Public domain (works are PD; Gutenberg adds no extra restriction) |

## Notes

- Each fetched file is ≤ 1 MB so the audit runs quickly + the repo stays small.
- Provenance entries here are checked-in-the-fetch-script — re-running `fetch_public.sh` regenerates this file.
- Adding a new source: add a `fetch <url> <subpath> <note>` line in `scripts/fetch_public.sh` and append an entry above.
EOF

echo
echo "Updated $CORPUS/SOURCES.md"
