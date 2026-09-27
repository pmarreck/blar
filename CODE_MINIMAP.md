# Code map

The project purpose is in [INTENT.md](INTENT.md), shared definitions in
[TERMINOLOGY.md](TERMINOLOGY.md), and active work in [PLAN.md](PLAN.md).
Run `dirtree --simple` for file-purpose notes alongside the directory tree.

## Build and entry points

| Path | Purpose |
|---|---|
| `build.zig` | Zig modules, C library/CLI, codec switches, unit tests, and test-binary installation. |
| `build.zig.zon` | Pinned Zig dependencies, including the upstream BLIP library; requires Zig 0.16.0. |
| `flake.nix`, `flake.lock` | Pinned Nix environment, sandboxed package build, and Zig test derivation. |
| `build`, `test`, `bm` | Build, unit/CLI suite, and archive benchmark entry points. |
| `blar` | Development CLI wrapper through `nix develop`. |
| `build_macos`, `build_and_run_macos` | Existing macOS app build and launch scripts. |
| `.mechatron-prime/targets` | Exact flake outputs requested from Mechatron Prime CI. |
| `MECHATRON_PRIME_CI.md` | Relative link to the shared CI operator guide. |
| `.github/workflows/` | Existing GitHub workflow definitions; distinct from the Mechatron target manifest. |

The intended platform set is macOS aarch64, Linux aarch64/x86_64, and Windows
aarch64/x86_64. The current flake exposes default systems through flake-utils;
the Mechatron manifest selects native x86_64-linux package and test outputs.
There is no top-level `build_all` script in this checkout.

## Archive core and interfaces

| Path | Purpose |
|---|---|
| `src/blar.h` | Public C ABI for archive, metadata, codec, and callback operations. |
| `src/blar.c` | CLI argument parsing, file I/O, progress reporting, and calls through the C ABI. |
| `src/blar_common.h` | Shared C entry/metadata collection and expansion helpers. |
| `src/lib.zig` | C ABI implementation and FFI tests; delegates to archive and codec modules. |
| `src/archive.zig` | In-memory archive creation, FILE/DIR metadata, and integrity verification. |
| `src/streaming.zig` | Two-pass archive creation using a spill file to bound memory. |
| `src/expansion.zig` | Format detection and dispatch for file expansion and reconstruction. |
| `src/poke.zig` | Archive structure mutation and reserialization. |
| `src/json_serde.zig` | Archive JSON serialization and reconstruction. |
| `src/io_singleton.zig` | Process-lifetime Zig 0.16 I/O context for internal operations reached through the C ABI. |

BLIP supplies generic integer/container operations through the external
`blip` module. The former local `src/dict.zig` is absent; this is no longer an
in-progress dependency carve-out.

## Compression and codecs

| Path | Purpose |
|---|---|
| `src/compression.zig` | Compression dispatch across LZMA2, zstd, lz4, and bzip2. |
| `src/compression_stub.zig` | API-compatible errors when compression support is disabled. |
| `src/lzma2.zig` | LZMA2 encode/decode wrapper. |
| `src/encryption.zig` | AEAD encryption and password derivation. |
| `src/jxl.zig` | libjxl bridge for JPEG and pixel transcoding. |
| `src/jxl_stub.zig` | Header-free replacement returning ImageSupportDisabled when enable_image=false. |
| `src/flac.zig` | FLAC bridge for PCM audio conversion, gated by enable_flac. |
| `src/pdf.zig` | PDF stream parsing and reconstruction. |
| `src/png.zig` | PNG chunk/pixel parsing and reconstruction. |
| `src/zip.zig`, `src/tar.zig` | ZIP and tar decomposition and reconstruction. |
| `src/bmp.zig`, `src/tga.zig`, `src/tiff.zig` | Raster image parsing and reconstruction. |
| `src/gif.zig` | GIF structure and LZW decoding. |
| `src/wav.zig`, `src/aiff.zig` | PCM audio container parsing and reconstruction. |
| `src/fits.zig`, `src/dicom.zig`, `src/nifti.zig` | Scientific and medical image container handling. |
| `src/deflate_emit.zig` | zlib and raw-deflate emission for reconstructed files. |
| `src/endian.zig` | Shared fixed-width endian readers. |
| `src/png_predictor.zig` | Paeth predictor shared by PNG and PDF decoding. |
| `src/zlib_io.zig` | Shared zlib decompression with format-specific error mapping at callers. |

Module existence does not establish byte-identical reconstruction for every
input; see the corpus audit and the open guarantees in INTENT.md.

## Tests, benchmarks, and GUI

| Path | Purpose |
|---|---|
| `tests/blar_test.sh`, `tests/blar_full_test.sh` | CLI archive and metadata integration tests. |
| `tests/cli/package_test` | Runs the installed CLI to catch missing ELF loaders or runtime libraries. |
| `tests/container_expansion_test.sh`, `tests/container_expansion_dual_test.sh` | File expansion and reconstruction checks. |
| `tests/pdf_container_test.sh`, `tests/png_container_test.sh` | PDF/PNG-specific integration tests. |
| `tests/compression_test.sh`, `tests/encryption_test.sh` | Compression and encryption CLI behavior. |
| `tests/streaming_test.sh` | Streaming creation and extraction tests. |
| `tests/segmentation_test.sh` | Splitting, joining, and reassembly tests. |
| `tests/explode_implode_test.sh` | Expanded directory representation and archive rebuilding. |
| `tests/audit/` | Empirical reconstruction audit scripts, public fixtures, and local-only results. |
| `bench/archive_bench.sh` | Archive throughput benchmark. |
| `bench/archive_bench_results.jsonl` | Versioned benchmark measurements. |
| `macos-app/Blarchiver/` | Swift GUI and C bridge to the archive API. |
| `macos-app/build.sh`, `macos-app/Makefile` | GUI build support. |
| `vendor/printable_binary/` | Vendored binary-to-text encoding. |
| `licenses/` | Third-party license texts. |

## Specifications and historical context

`BLAR_ARCHIVE_SPEC.md` specifies archive semantics and points upstream for the
BLIP wire primitives. `README.md` covers CLI use. `docs/plans/` retains older
designs, including pre-split work; `docs/plan_context/` preserves the old split
checklist and the repository reconciliation evidence. These records are
historical, not instructions to restart completed migrations.
