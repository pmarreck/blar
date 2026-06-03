# Code Minimap (blar)

Reflects the post-split tree. The BLIP encoding/container primitives are no longer in this repo â they come from the [`blip` dependency](https://github.com/pmarreck/BLIP) (consumed via `build.zig.zon` + `flake.nix` once Task 2.2 lands).

## Top level

- `build.zig`, `build.zig.zon` â Zig build script and dependency manifest. The BLIP dep gets added in Task 2.2.
- `flake.nix`, `flake.lock` â Nix flake. Provides Zig 0.15.2, hyperfine, libFLAC, libjxl, and (post-2.2) the BLIP flake input.
- `./build`, `./test`, `./bm`, `./build_all` â top-level driver scripts. `./build` uses `nix build` (sandboxed) to dodge Zig 0.15.2's macOS-26 libSystem stub gap; `./test` runs unit + CLI suites; `./build_all` cross-compiles for all 5 OS/arch combos.
- `blar` â dev convenience wrapper: `nix develop -c zig build blar -Doptimize=ReleaseFast -- "$@"`.
- `compile_commands.json` â generated for clangd. Regenerated when C build flags change.
- `inbox/` â incoming messages from sibling agents/projects (not for our own TODOs â those go in PLAN.md).
- `licenses/` â third-party license texts.
- `assets/` â sample data and fixtures used by tests/benchmarks.

## Specs and docs

- `README.md` â user-facing. CLI usage, container expansion, vs-tar comparison.
- `PROJECT_OVERVIEW.md` â goals, terminology, glossary, architecture.
- `PLAN.md` â Phase 2 task checklist (this carve-out).
- `BLIP_CONTAINER_SPEC.md` â REMOVED in Phase 2 (lives in BLIP repo now).
- `BLIP_SPEC.md`, `BLIP_SPEC_CONCISE.md` â REMOVED in Phase 2.
- `ZIG_RECENT_API_CHANGES.md` â Zig 0.15 idiom reminders (PascalCase enum tags, `b.path()`, etc.).
- `ZIG_0.15_TO_0.16_MIGRATION.md` â symlinked, upcoming-migration reference.
- `docs/` â supplementary documentation.

## C FFI surface (the public API)

- `src/blar.h` â public C header. Declares `blar_create*`, `blar_file_*`, `blar_verify*`, `blar_entry_*`, `blar_zip_*`, `blar_pdf_*`, codec sniffers `blar_is_*`, codec functions `blar_{bmp,png,gif,jxl,lzma2,tar,tga,tiff,wav,aiff,flac,fits,dicom}_*`, expansion entry points `blar_expand_file` / `blar_collapse_container`, callback typedefs `blar_phase_fn` / `blar_progress_fn` / `blar_compress_progress_fn`. Includes `<blip.h>` from the dep for BLIP-side primitives.
- `src/blar.c` â C CLI entry point. Argument parsing, stdin/stdout/path handling, dispatching to `blar_*` and `blip_*` calls. Adheres to CLI conventions in CLAUDE.md (UTF-8, `-h`/`--help`, `--about`, `--lang`, ANSI suppress, etc.).
- `src/blar_common.h` â shared C helpers: `fill_entry_metadata`, `mime_sort_entries`, `entry_list_*`, `expand_via_zig` dispatch table, path normalization. Includes `"blar.h"`.

## Zig core

- `src/lib.zig` â C FFI exports. Bridges archive-side calls to internal Zig modules. **Currently broken** â references deleted local files (`@import("blip")`, `blip.mini_blar_mod`); will be trimmed in Task 2.4 step 3 once BLIP dep is wired (Task 2.2). Will gain `blar_error_string` (Task 2.4 step 4).
- `src/dict.zig` â DICT/MAP/DIR serialization with FILE/DIR archive-side embellishments. **Currently broken** â imports `blip.zig`/`container.zig`/`container_types.zig`/`checksum.zig`/`leaf.zig` that were deleted in Task 2.3. Resolution depends on BLIP exposing `dict_mod` from the dep; archive-only FILE/DIR portion may move to a new `src/archive_dict.zig`.
- `src/expansion.zig` â single entry point for container expand/collapse. The C layer calls `blar_expand_file` / `blar_collapse_container`; this module dispatches to the codec modules. Format-specific logic does not live in C.
- `src/streaming.zig` â streaming archive creation. Two-pass spill-to-disk approach: pass 1 serializes entries to a temp file; pass 2 computes layout and stream-assembles. Memory bound is `O(largest single file)` instead of `O(total archive)`. Output is byte-identical to the in-memory `createFullArchive`.
- `src/json_serde.zig` â `to-json` / `from-json` codec. **Currently broken** â imports deleted `blip.zig`/`mini_blar.zig`/`poke.zig`. Needs rewiring against the BLIP dep's exported modules in Task 2.4.

## Codec modules

Each codec module exposes a sniffer (`isX`), a parser (decompose to byte-identical-reconstructable form), and a re-encoder (collapse).

- `src/jxl.zig` â JPEG XL via libjxl (`@cImport(@cInclude("jxl/encode.h"))`). Used by image codecs for lossless transcoding to/from JXL.
- `src/flac.zig` â libFLAC bridge for WAV/AIFF â FLAC. Gated on `build_options.enable_flac`.
- `src/pdf.zig` â PDF parsing: detects FlateDecode image streams (PNG-style zlib + filters) for JXL transcoding; preserves structural shell.
- `src/png.zig` â PNG: pixels â JXL; metadata chunks (tEXt/iCCP/pHYs) preserved.
- `src/zip.zig` â pure in-memory ZIP reader/writer (central directory parse, store + deflate). Used to decompose ZIPs for better LZMA2 ratios.
- `src/tar.zig` â tar parsing/repack for transparent expansion across the tar boundary.
- `src/bmp.zig`, `src/tga.zig`, `src/tiff.zig` â uncompressed raster â JXL pixels with compact header metadata.
- `src/gif.zig` â pure-Zig LZW decoder + JXL transcode. Original GIF preserved as metadata when JXL is smaller.
- `src/wav.zig`, `src/aiff.zig` â PCM container parsing; AIFF endian-flips on decode.
- `src/fits.zig`, `src/dicom.zig`, `src/nifti.zig` â scientific/medical pixel data â JXL; text headers / DICOM tags preserved as metadata.
- `src/lzma2.zig` â LZMA2 codec wrapper. **Currently broken** â imports deleted `container.zig`/`container_types.zig`/`checksum.zig`. Will rewire against the BLIP dep.
- `src/compression.zig` â multi-codec compression dispatch (LZMA2/zstd/lz4/bzip2 via `z7z`/`bzip2z`/`@cImport`). **Currently broken** â same import issue as above.
- `src/compression_stub.zig` â no-op fallback when `enable_compression=false`. Same public API; returns `error.UnsupportedCompression`.
- `src/encryption.zig` â AEAD encryption attribute (AES-256-GCM / ChaCha20-Poly1305) + KDF (Argon2id / PBKDF2-SHA256). Per-container, applied between compression and checksumming. **Currently broken** â same import issue.

## Shared helpers

- `src/endian.zig` — fixed-width little/big-endian integer readers (`readU16LE`/`readU32LE`/`readU16BE`/`readU32BE`) wrapping `std.mem.readInt`; shared by wav/bmp/dicom/gif/aiff/nifti to retire copy-pasted wrappers.
- `src/png_predictor.zig` — PNG Paeth predictor (RFC 2083 §6.6), shared by `png.zig` IDAT defiltering and `pdf.zig` FlateDecode predictor 14.
- `src/zlib_io.zig` — shared zlib (RFC 1950) decompression body used by PNG IDAT and PDF FlateDecode; callers map the generic `error.InvalidData` to a domain error as needed (png → `PngError.CorruptedData`).

## Tests

- `tests/blar_test.sh`, `tests/blar_full_test.sh` â primary blar CLI tests.
- `tests/compression_test.sh`, `tests/encryption_test.sh` â codec attribute coverage.
- `tests/container_expansion_test.sh`, `tests/container_expansion_dual_test.sh` â round-trip byte-identity tests for expanded containers.
- `tests/pdf_container_test.sh`, `tests/png_container_test.sh` â PDF/PNG-specific expansion tests.
- `tests/streaming_test.sh`, `tests/explode_implode_test.sh` â streaming creation + decomposition.
- `tests/segmentation_test.sh` â segment files (`split`/`join`/`reassemble`) â 36 tests covering Layer 5 segmentation CLI shipped recently (`b0bcef0`, `14227c7`, `5322698`, `ba5bd79`).
- The master `./test` runner accumulates all subtest exit codes. Per CLAUDE.md, never use `set -euo pipefail` in tests.

## Benchmarks

- `bench/archive_bench.sh` â archive create/extract throughput.
- `bench/archive_bench_results.jsonl` â committed log of historical results; loud regression alerts on % swings.

## macOS GUI app

- `macos-app/BlarArchive/` â Swift app, calls into C FFI. Built via `macos-app/build.sh` / `macos-app/Makefile`.

## Vendored

- `vendor/printable_binary/printable_binary.zig` â printable-binary text encoding (used by `to-json`/`peek --raw` for binary-in-text-channel transport).

## Cleanup notes (deferred)

- The top-level `miniblar` wrapper (`nix develop -c zig build miniblar -- "$@"`) is **dead** â mini_blar moved to its own repo. Should be removed as part of Task 2.5 cleanup.
- `inbox/` â review for stale BLIP-side messages.
