#!/usr/bin/env bash
# blar empirical byte-identity audit runner.
#
# For each file in corpus_{synthetic,public,local}/<format>/<generator>/:
#   1. SHA256 the original
#   2. blar create -z -o <tmp> <file>
#   3. blar extract <tmp> -C <out>
#   4. SHA256 the extracted file
#   5. If hashes differ: try difz to measure residual patch size
#   6. Record (format, generator, path, size, byte_identical, residual_bytes, time_ms)
#
# Outputs:
#   results/audit-YYYY-MM-DD.csv
#   results/audit-YYYY-MM-DD.md  (aggregated report)
#
# Per CLAUDE.md: no `set -e` in test scripts. `set -u` only.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$AUDIT_DIR/../.." && pwd)"

BLAR="${BLAR:-$PROJECT_DIR/zig-out/bin/blar}"
DIFZ="${DIFZ:-difz}"  # may not be installed; we degrade gracefully
TODAY=$(date +%Y-%m-%d)

CORPORA=()
FORMAT_FILTER=""
JSON_OUT=""
USE_DIFZ=1

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --corpus {public|local|all}             Which corpus to run (default: all).
                                          public = synthetic + publicly-sourced (committed).
                                          local  = NAS-sampled cross-section (gitignored).
  --format <ext>                          Restrict to one format (e.g. pdf, png)
  --json <path>                           Emit JSON to <path> in addition to CSV+MD
  --no-difz                               Skip difz residual measurement
  -h, --help                              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --corpus)
            shift
            case "$1" in
                public|local) CORPORA=("$1") ;;
                all|"") CORPORA=(public local) ;;
                *) echo "unknown corpus: $1" >&2; exit 2 ;;
            esac
            ;;
        --format) shift; FORMAT_FILTER="$1" ;;
        --json) shift; JSON_OUT="$1" ;;
        --no-difz) USE_DIFZ=0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

if [[ ${#CORPORA[@]} -eq 0 ]]; then
    CORPORA=(public local)
fi

if [[ ! -x "$BLAR" ]]; then
    echo "Building blar (ReleaseFast)..." >&2
    (cd "$PROJECT_DIR" && ./build) || { echo "FATAL: blar build failed" >&2; exit 1; }
fi

if [[ ! -x "$BLAR" ]]; then
    echo "FATAL: blar binary still missing at $BLAR after build" >&2
    exit 1
fi

if [[ $USE_DIFZ -eq 1 ]] && ! command -v "$DIFZ" >/dev/null 2>&1; then
    echo "WARNING: difz not in PATH; running without residual measurement" >&2
    USE_DIFZ=0
fi

mkdir -p "$AUDIT_DIR/results"
CSV="$AUDIT_DIR/results/audit-$TODAY.csv"
MD="$AUDIT_DIR/results/audit-$TODAY.md"

# Header row. Paths may contain commas / quotes; CSV writes quote the path
# field so Python csv.DictReader parses correctly.
echo "format,generator,path,size,archive_size,byte_identical,residual_bytes,residual_ratio,time_ms" > "$CSV"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

audit_one() {
    local corpus="$1"
    local format="$2"
    local generator="$3"
    local file="$4"
    local rel_path="${file#"$AUDIT_DIR/corpus_$corpus/"}"
    local size; size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    local orig_sha; orig_sha=$(shasum -a 256 "$file" | awk '{print $1}')

    local workdir; workdir=$(mktemp -d "$TMP_ROOT/audit.XXXXXX")
    local archive="$workdir/test.blar"
    local outdir="$workdir/out"
    mkdir -p "$outdir"

    local t0; t0=$(python3 -c 'import time; print(int(time.time()*1000))')
    # Quote rel_path in CSV — book titles etc. may contain commas / quotes.
    local quoted_path; quoted_path=$(printf '"%s"' "${rel_path//\"/\"\"}")
    if ! "$BLAR" create -z -o "$archive" "$file" >/dev/null 2>&1; then
        echo "$format,$generator,$quoted_path,$size,,FAIL_CREATE,,,," >> "$CSV"
        rm -rf "$workdir"
        return
    fi
    if ! "$BLAR" extract "$archive" -C "$outdir" >/dev/null 2>&1; then
        echo "$format,$generator,$quoted_path,$size,,FAIL_EXTRACT,,,," >> "$CSV"
        rm -rf "$workdir"
        return
    fi
    local t1; t1=$(python3 -c 'import time; print(int(time.time()*1000))')

    local extracted; extracted=$(find "$outdir" -type f | head -1)
    local archive_size; archive_size=$(stat -f%z "$archive" 2>/dev/null || stat -c%s "$archive" 2>/dev/null)
    local extr_sha; extr_sha=$(shasum -a 256 "$extracted" | awk '{print $1}')

    local byte_identical
    local residual_bytes=""
    local residual_ratio=""
    if [[ "$orig_sha" == "$extr_sha" ]]; then
        byte_identical=true
    else
        byte_identical=false
        if [[ $USE_DIFZ -eq 1 ]]; then
            local patch="$workdir/patch.difz"
            if "$DIFZ" "$extracted" "$file" -o "$patch" >/dev/null 2>&1; then
                residual_bytes=$(stat -f%z "$patch" 2>/dev/null || stat -c%s "$patch" 2>/dev/null)
                if [[ "$size" -gt 0 ]]; then
                    residual_ratio=$(awk "BEGIN{printf \"%.4f\", $residual_bytes/$size}")
                fi
            fi
        fi
    fi

    local elapsed=$((t1 - t0))
    echo "$format,$generator,$quoted_path,$size,$archive_size,$byte_identical,$residual_bytes,$residual_ratio,$elapsed" >> "$CSV"
    rm -rf "$workdir"
}

# Walk corpora
for corpus in "${CORPORA[@]}"; do
    corpus_dir="$AUDIT_DIR/corpus_$corpus"
    [[ -d "$corpus_dir" ]] || continue
    for format_dir in "$corpus_dir"/*; do
        [[ -d "$format_dir" ]] || continue
        format=$(basename "$format_dir")
        if [[ -n "$FORMAT_FILTER" && "$format" != "$FORMAT_FILTER" ]]; then
            continue
        fi
        for generator_dir in "$format_dir"/*; do
            [[ -d "$generator_dir" ]] || continue
            generator=$(basename "$generator_dir")
            find "$generator_dir" -type f | while read -r file; do
                audit_one "$corpus" "$format" "$generator" "$file"
            done
        done
    done
done

# Aggregate into markdown report
python3 - "$CSV" "$MD" <<'PYEOF'
import csv, sys
from collections import defaultdict

csv_path = sys.argv[1]
md_path = sys.argv[2]

records = []
with open(csv_path) as f:
    reader = csv.DictReader(f)
    for row in reader:
        records.append(row)

# Per (format, generator) stats
by_pair = defaultdict(list)
for r in records:
    by_pair[(r['format'], r['generator'])].append(r)

with open(md_path, 'w') as f:
    f.write(f"# blar byte-identity audit — {csv_path.split('/')[-1].replace('audit-','').replace('.csv','')}\n\n")
    f.write(f"Total files audited: **{len(records)}**\n\n")

    # Overall summary
    by_id = [r for r in records if r['byte_identical'] == 'true']
    f.write(f"- Byte-identical: **{len(by_id)} / {len(records)} ({100*len(by_id)/max(1,len(records)):.1f}%)**\n")
    diverged = [r for r in records if r['byte_identical'] == 'false']
    failed = [r for r in records if r['byte_identical'].startswith('FAIL')]
    f.write(f"- Diverged (content-only): {len(diverged)}\n")
    f.write(f"- Failed (create/extract error): {len(failed)}\n\n")

    f.write("## Per-format breakdown\n\n")
    f.write("| Format | Generator | N | Byte-identical | Median residual | Median ratio | Notes |\n")
    f.write("|---|---|---|---|---|---|---|\n")

    def _safe_int(s):
        try: return int(s) if s and s.lstrip('-').isdigit() else None
        except Exception: return None
    def _safe_float(s):
        try: return float(s) if s else None
        except Exception: return None

    for (fmt, gen), rs in sorted(by_pair.items()):
        n = len(rs)
        bi = sum(1 for r in rs if r.get('byte_identical') == 'true')
        residuals = [v for r in rs if (v := _safe_int(r.get('residual_bytes',''))) is not None]
        ratios = [v for r in rs if (v := _safe_float(r.get('residual_ratio',''))) is not None]
        med_res = ''
        med_ratio = ''
        if residuals:
            residuals.sort(); med_res = str(residuals[len(residuals)//2])
        if ratios:
            ratios.sort(); med_ratio = f"{ratios[len(ratios)//2]:.4f}"
        note = ''
        if med_ratio:
            mr = float(med_ratio)
            if mr < 0.01:  note = 'difz backstop: tiny patch — viable'
            elif mr < 0.5: note = 'difz backstop: feasible'
            else:          note = 'difz backstop: patch too large; raw-store wins'
        f.write(f"| {fmt} | {gen} | {n} | {bi}/{n} ({100*bi/max(1,n):.0f}%) | {med_res} | {med_ratio} | {note} |\n")

    f.write("\n## Failures\n\n")
    if failed:
        for r in failed[:50]:
            f.write(f"- `{r['format']}/{r['generator']}/{r['path']}` — {r['byte_identical']}\n")
        if len(failed) > 50:
            f.write(f"- ... and {len(failed) - 50} more\n")
    else:
        f.write("(none)\n")
PYEOF

echo
echo "=== Audit complete ==="
echo "  CSV: $CSV"
echo "  MD:  $MD"
