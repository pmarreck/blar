#!/usr/bin/env bash
# Random-sample N files per format from /Volumes/Fileserver into
# corpus_local/<format>/wild/.
#
# Files go to a single "wild" generator bucket initially. A follow-up pass
# can classify by EXIF / creator metadata / file magic to split into
# per-generator subdirs once we see what's interesting in the audit results.
#
# Reproducible via fixed shuffle seed (override with --seed).
#
# Output mirrors corpus_synthetic / corpus_public structure for run_audit.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CORPUS="$AUDIT_DIR/corpus_local"

NAS_ROOT="${NAS_ROOT:-/Volumes/Fileserver}"
N="${N:-50}"
SEED="${SEED:-42}"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --nas-root <path>     Root to sample from (default: /Volumes/Fileserver)
  --n <int>             Sample N files per format (default: 50)
  --seed <int>          Random seed (default: 42)
  --format <ext>        Restrict to one format
  --dry-run             Show what would be sampled without copying
  -h, --help            This help
EOF
}

FORMAT_FILTER=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nas-root) shift; NAS_ROOT="$1" ;;
        --n) shift; N="$1" ;;
        --seed) shift; SEED="$1" ;;
        --format) shift; FORMAT_FILTER="$1" ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

if [[ ! -d "$NAS_ROOT" ]]; then
    echo "FATAL: $NAS_ROOT not mounted" >&2
    exit 1
fi

# Per-format find expressions (extensions; case-insensitive)
# Per-format ripgrep glob arguments. ripgrep's `--files` mode parallelizes
# directory traversal; on a NAS-mounted tree it's typically 4–8× faster than
# `find` because filesystem-metadata roundtrips overlap. macOS AppleDouble
# (._*) sidecars are excluded via `--glob '!._*'`.
declare -A RG_GLOBS
RG_GLOBS=(
    [pdf]='-g *.pdf'
    [png]='-g *.png'
    [jpeg]='-g *.jpg -g *.jpeg'
    [bmp]='-g *.bmp'
    [tga]='-g *.tga'
    [tiff]='-g *.tiff -g *.tif'
    [gif]='-g *.gif'
    [wav]='-g *.wav'
    [aiff]='-g *.aif -g *.aiff'
    [flac]='-g *.flac'
    [docx]='-g *.docx'
    [xlsx]='-g *.xlsx'
    [pptx]='-g *.pptx'
    [odt]='-g *.odt'
    [epub]='-g *.epub'
    [zip]='-g *.zip'
    [jar]='-g *.jar'
    [gzip]='-g *.gz -g *.tgz'
)

if ! command -v rg >/dev/null 2>&1; then
    echo "FATAL: ripgrep (rg) not in PATH. Install via nix devshell or 'brew install ripgrep'." >&2
    exit 1
fi

for format in "${!RG_GLOBS[@]}"; do
    if [[ -n "$FORMAT_FILTER" && "$format" != "$FORMAT_FILTER" ]]; then
        continue
    fi
    dest_dir="$CORPUS/$format/wild"

    # Idempotency: skip if the dest already has ≥ N files (already sampled).
    existing=0
    if [[ -d "$dest_dir" ]]; then
        existing=$(find "$dest_dir" -type f 2>/dev/null | wc -l | awk '{print $1}')
    fi
    if [[ "$existing" -ge "$N" ]]; then
        echo "  $format: already populated ($existing files in $dest_dir) — skipping"
        continue
    fi

    globs="${RG_GLOBS[$format]}"

    # Enumerate via rg --files (parallel walk, much faster than find on a
    # network-mounted tree). Then deterministic shuffle via awk-seeded rand,
    # take top N. Exclude macOS AppleDouble sidecars.
    # shellcheck disable=SC2086  # $globs is intentionally word-split
    candidates=$(rg --files --no-ignore --no-messages --hidden \
            $globs --glob '!._*' "$NAS_ROOT" 2>/dev/null \
        | awk -v seed="$SEED" 'BEGIN{srand(seed)} {print rand() "\t" $0}' \
        | sort -k1,1n \
        | cut -f2- \
        | head -n "$N")

    count=$(echo "$candidates" | grep -c .)

    if [[ "$count" -eq 0 ]]; then
        echo "  $format: 0 files found on NAS (skipping)"
        continue
    fi

    echo "  $format: sampling $count of N=$N (seed=$SEED)"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "$candidates" | head -5 | sed 's/^/      /'
        [[ $(echo "$candidates" | wc -l) -gt 5 ]] && echo "      ... ($(echo "$candidates" | wc -l) total)"
        continue
    fi

    mkdir -p "$dest_dir"
    # Copy with rename-on-collision: use a hash of the source path as prefix
    # so identical filenames from different source dirs don't collide.
    i=0
    while IFS= read -r src; do
        [[ -z "$src" ]] && continue
        i=$((i+1))
        bn=$(basename "$src")
        # 8-char path hash + original basename
        hash=$(printf '%s' "$src" | shasum -a 256 | cut -c1-8)
        cp -p "$src" "$dest_dir/${hash}_${bn}" 2>/dev/null \
            || echo "    WARNING: failed to copy $src" >&2
    done <<< "$candidates"

    echo "    → $dest_dir ($(find "$dest_dir" -type f | wc -l | tr -d ' ') files total)"
done

echo
echo "Local corpus sampling complete."
echo "Total files in corpus_local: $(find "$CORPUS" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "NOTE: corpus_local/ is gitignored. Files contain potentially-sensitive data;"
echo "review before promoting any to corpus_public/."
