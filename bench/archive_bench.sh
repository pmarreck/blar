#!/usr/bin/env bash
# =============================================================================
# Archive creation benchmark suite
# =============================================================================
# Benchmarks the full archive creation pipeline: collect → expand → serialize
# Tests both in-memory and streaming paths at various input sizes.
#
# Usage: ./bm              (runs this + the Zig benchmark)
#        bash bench/archive_bench.sh   (runs just this)
#
# Results logged to bench/archive_bench_results.jsonl (git-tracked).
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -z ${IN_NIX_SHELL:-} ]]; then
    exec nix develop "$PROJECT_DIR" -c bash "$0" "$@"
fi
BLAR="$PROJECT_DIR/zig-out/bin/blar"
RESULTS_FILE="$PROJECT_DIR/bench/archive_bench_results.jsonl"
TIMESTAMP=$(date +%s)

# Build optimized
echo "Building blar (ReleaseFast)..."
(cd "$PROJECT_DIR" && nix develop -c zig build -Doptimize=ReleaseFast) \
  || { echo "FATAL: build failed"; exit 1; }

# Check for DEBUG BUILD
if "$BLAR" --about 2>&1 | grep -qi "DEBUG BUILD"; then
  echo "ERROR: Benchmark binary is a DEBUG BUILD. Aborting."
  exit 1
fi

TMPDIR_BENCH="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BENCH"' EXIT

# =============================================================================
# Helper: generate test data
# =============================================================================

generate_bmp() {
    local path="$1" width="$2" height="$3"
    "$PROJECT_DIR/tests/helpers/fixtures" bmp "$path" "$width" gradient "$height" || exit 1
}

generate_text_file() {
    local path="$1" size_kb="$2"
    dd if=/dev/urandom bs=1024 count="$size_kb" 2>/dev/null | base64 > "$path"
}

log_result() {
    local name="$1" ns_per_op="$2" throughput="$3"
    echo "{\"name\":\"$name\",\"ns_per_op\":$ns_per_op,\"throughput_mb_s\":$throughput,\"timestamp\":$TIMESTAMP}" >> "$RESULTS_FILE"
    printf "  %-40s %10d ns/op  %8.1f MB/s\n" "$name" "$ns_per_op" "$throughput"
}

# Time a command, return nanoseconds
time_ns() {
    local start end
    start=$(date +%s%N)
    eval "$@"
    end=$(date +%s%N)
    echo $((end - start))
}

# =============================================================================
# Benchmark 1: Small archive (10 text files, no expansion)
# =============================================================================
echo ""
echo "=== Benchmark 1: Small archive (10 text files, ~100KB total) ==="
mkdir -p "$TMPDIR_BENCH/b1/input"
for i in $(seq 1 10); do
    generate_text_file "$TMPDIR_BENCH/b1/input/file_$i.txt" 10
done
TOTAL_KB=100

# In-memory
NS=$(time_ns "(cd $TMPDIR_BENCH/b1 && $BLAR create -z -f -o out_inmem.blar input 2>/dev/null)")
THROUGHPUT=$(luajit -e 'io.write(string.format("%.1f", tonumber(arg[1]) / 1024 / (tonumber(arg[2]) / 1e9)))' - "$TOTAL_KB" "$NS" < /dev/null)
log_result "small_10files_inmem" "$NS" "$THROUGHPUT"

# Streaming
NS=$(time_ns "(cd $TMPDIR_BENCH/b1 && $BLAR create -z -f --streaming -o out_stream.blar input 2>/dev/null)")
THROUGHPUT=$(luajit -e 'io.write(string.format("%.1f", tonumber(arg[1]) / 1024 / (tonumber(arg[2]) / 1e9)))' - "$TOTAL_KB" "$NS" < /dev/null)
log_result "small_10files_streaming" "$NS" "$THROUGHPUT"

# =============================================================================
# Benchmark 2: Medium archive with BMP expansion (10 BMPs, ~3MB total)
# =============================================================================
echo ""
echo "=== Benchmark 2: Medium archive with BMP expansion (10 BMPs, ~3MB) ==="
mkdir -p "$TMPDIR_BENCH/b2/input"
for i in $(seq 1 10); do
    generate_bmp "$TMPDIR_BENCH/b2/input/image_$i.bmp" 100 100
done
TOTAL_KB=$((100 * 100 * 3 * 10 / 1024))

# In-memory with expansion
NS=$(time_ns "(cd $TMPDIR_BENCH/b2 && $BLAR create -z -f -o out_inmem.blar input 2>/dev/null)")
THROUGHPUT=$(luajit -e 'io.write(string.format("%.1f", tonumber(arg[1]) / 1024 / (tonumber(arg[2]) / 1e9)))' - "$TOTAL_KB" "$NS" < /dev/null)
log_result "medium_10bmp_inmem_expand" "$NS" "$THROUGHPUT"

# Streaming with expansion
NS=$(time_ns "(cd $TMPDIR_BENCH/b2 && $BLAR create -z -f --streaming -o out_stream.blar input 2>/dev/null)")
THROUGHPUT=$(luajit -e 'io.write(string.format("%.1f", tonumber(arg[1]) / 1024 / (tonumber(arg[2]) / 1e9)))' - "$TOTAL_KB" "$NS" < /dev/null)
log_result "medium_10bmp_streaming_expand" "$NS" "$THROUGHPUT"

# In-memory without expansion
NS=$(time_ns "(cd $TMPDIR_BENCH/b2 && $BLAR create -z -f --no-expand-containers -o out_noexpand.blar input 2>/dev/null)")
THROUGHPUT=$(luajit -e 'io.write(string.format("%.1f", tonumber(arg[1]) / 1024 / (tonumber(arg[2]) / 1e9)))' - "$TOTAL_KB" "$NS" < /dev/null)
log_result "medium_10bmp_inmem_noexpand" "$NS" "$THROUGHPUT"

# =============================================================================
# Benchmark 3: Large archive (100 text files, ~10MB total)
# =============================================================================
echo ""
echo "=== Benchmark 3: Large archive (100 text files, ~10MB) ==="
mkdir -p "$TMPDIR_BENCH/b3/input"
for i in $(seq 1 100); do
    generate_text_file "$TMPDIR_BENCH/b3/input/file_$i.txt" 100
done
TOTAL_KB=10000

# In-memory
NS=$(time_ns "(cd $TMPDIR_BENCH/b3 && $BLAR create -z -f -o out_inmem.blar input 2>/dev/null)")
THROUGHPUT=$(luajit -e 'io.write(string.format("%.1f", tonumber(arg[1]) / 1024 / (tonumber(arg[2]) / 1e9)))' - "$TOTAL_KB" "$NS" < /dev/null)
log_result "large_100files_inmem" "$NS" "$THROUGHPUT"

# Streaming
NS=$(time_ns "(cd $TMPDIR_BENCH/b3 && $BLAR create -z -f --streaming -o out_stream.blar input 2>/dev/null)")
THROUGHPUT=$(luajit -e 'io.write(string.format("%.1f", tonumber(arg[1]) / 1024 / (tonumber(arg[2]) / 1e9)))' - "$TOTAL_KB" "$NS" < /dev/null)
log_result "large_100files_streaming" "$NS" "$THROUGHPUT"

# =============================================================================
# Compare last run against previous baseline
# =============================================================================
echo ""
echo "=== Results Summary ==="
echo "Results logged to: $RESULTS_FILE"
echo ""

# Count entries
if [[ -f "$RESULTS_FILE" ]]; then
    ENTRIES=$(wc -l < "$RESULTS_FILE" | tr -d ' ')
    echo "Total historical entries: $ENTRIES"
fi
