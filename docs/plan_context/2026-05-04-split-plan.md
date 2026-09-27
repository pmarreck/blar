# blar Implementation Plan

> **You are the blar agent.** Your working directory is `/Users/pmarreck/Documents-CloudManaged/blar/`. Your job: carve this working copy of the original BLIP umbrella down to a focused archive-only project, set up the new `pmarreck/blar` GitHub repo, wire BLIP as a dep, push, tag.
>
> **Use:** `superpowers:subagent-driven-development` or `superpowers:executing-plans` to work through the tasks. Steps use `- [ ]` checkboxes.
>
> **Important — wait for upstream:** the BLIP carve-out (Phase 1 in the canonical plan) must finish before you can wire the BLIP dep. The BLIP agent's signal is **`v3.0.0` tagged on `pmarreck/BLIP`**. Until that exists, you can do Tasks 2.1, 2.3, 2.4, 2.5 (preparatory work that doesn't need the dep yet), but Task 2.2 (BLIP dep wiring) must wait.

## Provenance

This working copy was created on 2026-05-04 by `cp -a` from `/Users/pmarreck/Documents-CloudManaged/BLIP/` at commit `559ddbf docs(plan): lock in symbol-rename to blar_* in Phase 2`. It retains the full git history of the original BLIP umbrella.

The complete multi-phase split plan (Phases 1-4 covering all three projects) lives in `pmarreck/BLIP`'s `PLAN.md`. This file extracts and personalizes Phase 2 only.

## Goal

Take this working copy and reshape it into the `pmarreck/blar` repo:
- Drop all BLIP-side source (varint, LP envelope, generic containers, SEGMENT primitive, comparison varints, BLIP CLIs, BLIP specs).
- Drop the mini_blar source (`src/mini_blar.zig`, `src/miniblar.c`, `tests/miniblar_test.sh`) — that goes to its own sister project.
- Keep: archive-format-specific source (`src/blar.c`, `src/blar_common.h`, `src/dict.zig`'s FILE/DIR portion, `src/streaming.zig`, `src/expansion.zig`, all codec modules), archive CLI tests, container-expansion tests, the macOS GUI app.
- Wire BLIP as an external dep via `build.zig.zon` + `flake.nix`.
- Rename FFI symbols: `blip_archive_*` → `blar_*`, `blip_zip_*` → `blar_zip_*`, etc. (full table in Task 2.4 below).
- Rename the C header from `src/blip.h` → `src/blar.h`.
- Get all archive-side tests green, push to `pmarreck/blar` on `yolo` branch, tag `v3.0.0`.

## Pre-flight context

**Project conventions (from CLAUDE.md):**
- Main branch is **`yolo`** across all repos. Never assume `main`/`master`.
- TDD-strict where applicable: failing test first, run it, confirm fail, minimal impl, rerun, confirm pass.
- `./test` runs the full suite. `./build` builds via `nix build`. `./bm` runs benchmarks.
- Use `codescan` MCP tools (`mcp__codescan__read_file`, `mcp__codescan__search`, `mcp__codescan__replace_lines`) for code work; fall back to `Read`/`Bash`/`grep` for non-indexed operations.
- Tabs over spaces. `#!/usr/bin/env <interp>` for scripts.
- **Never** use `set -euo pipefail` in test scripts (only `set -u`).
- Commit messages: no AI attribution lines.
- Garnix CI is org-wide; just having `flake.nix` with `packages` and `checks` defined enables it.
- Use `nix develop -c zig build test` for tests (not bare `zig build test`).

**The BLIP dep you'll consume:**
- Repo: `pmarreck/BLIP`
- Tag: `v3.0.0` (must exist before Task 2.2)
- Provides: `libblip.a`, `src/blip.h`, the `blip` Zig module, `blip-bench`/`blip-benchmark` binaries (the binaries you don't need; you import the `blip` Zig module + link the C lib).
- Public BLIP FFI symbols (still `blip_*` prefix): `blip_encode`, `blip_decode`, `blip_segment_*`, `blip_xxhash64`, `blip_peek`, `blip_poke`, `blip_to_json`, `blip_from_json`, `blip_compress_container`, `blip_decompress_container`, `blip_encrypt_container`, `blip_decrypt_container`, `blip_decode_printable_binary`, `blip_encode_printable_binary`, `blip_normalize_path`, `blip_free`, `blip_free_content`, `blip_error_string`.

**Recently shipped (carry forward into blar):**
- Layer 5 segmentation CLI (commits `b0bcef0`, `14227c7`, `5322698`, `ba5bd79`): `blar segment`, `blar split`, `blar join`, `blar reassemble`, `blar create --segment-size`, `blar create --segment-count`, `blar create --manifest`, segment-file detection on `list/extract/verify/info`. Tests in `tests/segmentation_test.sh` (36 tests). All this stays.
- `156cbf2` perf optimization on BLIP encode/decode is in BLIP, not blar.

## Phase 2 tasks

### Task 2.1: Set up blar repo on GitHub

**Files:**
- Modify: `.git/config` (remote URL)
- Create: `pmarreck/blar` on GitHub

- [ ] **Step 1: Create the GitHub repo**

```bash
gh repo create pmarreck/blar --public --description "BLAR archive format — built on BLIP" --no-readme
```

- [ ] **Step 2: Set the new remote**

```bash
git remote set-url origin git@github.com:pmarreck/blar.git
git branch -M yolo
git push -u origin yolo
```

- [ ] **Step 3: Verify**

```bash
git remote -v
git log -1 --oneline
```

Expected: remote = `pmarreck/blar`, HEAD = the same commit you started on (`559ddbf` or whatever the BLIP umbrella was at when copied).

### Task 2.2: Wait for BLIP `v3.0.0`, then add it as a dep

**Wait condition:** `gh release view v3.0.0 --repo pmarreck/BLIP --json tagName --jq .tagName` returns `v3.0.0`.

- [ ] **Step 1: Verify BLIP `v3.0.0` exists**

```bash
until gh release view v3.0.0 --repo pmarreck/BLIP --json tagName --jq .tagName 2>/dev/null | grep -q v3.0.0; do
    echo "Waiting for BLIP v3.0.0 tag…"
    sleep 60
done
echo "BLIP v3.0.0 is published. Proceeding."
```

- [ ] **Step 2: Add BLIP to `build.zig.zon`**

Get the tarball URL:
```bash
BLIP_TAR_URL=$(gh release view v3.0.0 --repo pmarreck/BLIP --json tarballUrl --jq .tarballUrl)
echo "$BLIP_TAR_URL"
```

In `build.zig.zon`, add a `blip` entry to `.dependencies`:
```zig
.dependencies = .{
    .blip = .{
        .url = "https://github.com/pmarreck/BLIP/archive/refs/tags/v3.0.0.tar.gz",
        .hash = "",  // see Step 5
    },
    // … any existing deps
},
```

- [ ] **Step 3: Add BLIP as a Nix flake input**

In `flake.nix`:
```nix
inputs.blip.url = "github:pmarreck/BLIP/v3.0.0";
inputs.blip.inputs.nixpkgs.follows = "nixpkgs";
```

In the package outputs, expose `blip.packages.${system}.default` as a build dep where `libblip.a` is needed.

- [ ] **Step 4: Update `build.zig` to consume the BLIP dep**

Replace the local `blip_module` (a `b.createModule` call sourcing from `src/blip.zig`) with:
```zig
const blip_dep = b.dependency("blip", .{
    .target = target,
    .optimize = optimize,
});
const blip_module = blip_dep.module("blip");
```

For C-side linkage, `blar.linkLibrary(blip_dep.artifact("blip"))` and `blar.addIncludePath(blip_dep.path("src"))` for the header.

- [ ] **Step 5: Hash the dep**

```bash
nix build 2>&1 | tail -10
```

If it complains about hash mismatch, copy the `got: sha256-...` value into `build.zig.zon` and `flake.nix`.

If you see `error: hash mismatch in fixed-output derivation` — see the `fix-zig-deps-hash` skill.

- [ ] **Step 6: Commit**

```bash
git add build.zig.zon build.zig flake.nix flake.lock
git commit -m "chore(split): add BLIP v3.0.0 as external dep"
```

### Task 2.3: Remove BLIP-side files (now provided by the dep)

**Files to DELETE from blar's tree** (these come from the BLIP dep):

- [ ] **Step 1: Delete BLIP source modules**

```bash
git rm src/blip.zig src/blip.h \
       src/container_types.zig src/container.zig \
       src/checksum.zig src/leaf.zig src/array.zig src/peek.zig src/poke.zig \
       src/segmentation.zig \
       src/encoding.zig src/leb128.zig src/protobuf_varint.zig src/asn1_length.zig \
       src/prefix_varint.zig src/sqlite_varint.zig src/bignum.zig src/fuzz.zig \
       src/benchmark.zig src/main.zig
```

- [ ] **Step 2: Delete BLIP specs and BLIP-only tests**

```bash
git rm BLIP_SPEC.md BLIP_SPEC_CONCISE.md BLIP_CONTAINER_SPEC.md BLIP_SIGIL_REGISTRY.md \
       docs/transport_embedding.md \
       tests/peek_test.sh tests/poke_test.sh tests/json_test.sh \
       tests/binary_format_test.sh tests/text_roundtrip_test.sh tests/tri_representation_test.sh
```

(If `BLIP_SIGIL_REGISTRY.md` doesn't exist yet, ignore — it's created during BLIP's Phase 1.)

- [ ] **Step 3: Delete mini_blar's content (it's a separate project)**

```bash
git rm src/mini_blar.zig src/miniblar.c tests/miniblar_test.sh
```

- [ ] **Step 4: Verify what's left**

```bash
ls src/
ls tests/
```

Expected `src/`:
- `blar.c`, `blar_common.h`
- `dict.zig` (FILE/DIR portion only — see Task 2.4 Step 0)
- `streaming.zig`, `expansion.zig`
- `lib.zig` (will be trimmed to archive-side FFI in Task 2.4)
- All codec modules: `jxl.zig`, `flac.zig`, `pdf.zig`, `png.zig`, `bmp.zig`, `tar.zig`, `tiff.zig`, `gif.zig`, `tga.zig`, `wav.zig`, `aiff.zig`, `fits.zig`, `dicom.zig`, `nifti.zig`, `zip.zig`

Expected `tests/`:
- `blar_test.sh`, `blar_full_test.sh`
- `compression_test.sh`, `encryption_test.sh`
- `container_expansion_test.sh`, `container_expansion_dual_test.sh`
- `pdf_container_test.sh`, `png_container_test.sh`
- `streaming_test.sh`, `explode_implode_test.sh`
- `segmentation_test.sh` (the blar-CLI portion)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(split): remove BLIP-side files; blar consumes BLIP via dep"
```

### Task 2.4: Trim `lib.zig`, rename header, rename FFI symbols

**Files:**
- Modify: `src/lib.zig` (remove BLIP-side exports; keep archive-side; rename to `blar_*`)
- Rename: `src/blip.h` → `src/blar.h` (then update all `#include "blip.h"` references)

- [ ] **Step 0: If Task 1.5 didn't run upstream, split FILE/DIR out of dict.zig now**

Phase 1 task 1.5 was supposed to remove FILE/DIR archive-specific code from BLIP's `dict.zig`. If for some reason it didn't, you may have a `dict.zig` here that imports BLIP types. Verify:

```bash
grep -n "@import" src/dict.zig | head
```

Should import only from the `blip` module, not `@import("container.zig")` etc. If it imports local files, the FILE/DIR code needs to be moved into a new `src/archive_dict.zig` (or merged into another file) that uses the `blip.dict_mod` for the underlying DICT serialization.

- [ ] **Step 1: Rename `blip.h` → `blar.h`**

```bash
git mv src/blip.h src/blar.h
sed -i '' 's|"blip\.h"|"blar.h"|g' src/blar.c src/blar_common.h
```

(macOS `sed -i ''`. On Linux use `sed -i`.)

- [ ] **Step 2: Apply the symbol rename across the source tree**

This is a single-pass `sed` over every source and test file. The rename rule: every FFI symbol that lives in blar drops the `blip_` prefix and gains `blar_`. Symbols staying in BLIP (provided by the dep) keep `blip_`.

```bash
SED_SCRIPT='
s/\bblip_archive_create_full\b/blar_create_full/g
s/\bblip_archive_create_streaming\b/blar_create_streaming/g
s/\bblip_archive_create\b/blar_create/g
s/\bblip_archive_file_count\b/blar_file_count/g
s/\bblip_archive_file_path\b/blar_file_path/g
s/\bblip_archive_file_content_by_path\b/blar_file_content_by_path/g
s/\bblip_archive_file_content\b/blar_file_content/g
s/\bblip_archive_file_verify\b/blar_file_verify/g
s/\bblip_archive_verify_merkle\b/blar_verify_merkle/g
s/\bblip_archive_verify\b/blar_verify/g
s/\bblip_archive_entry_type\b/blar_entry_type/g
s/\bblip_archive_entry_metadata_full\b/blar_entry_metadata_full/g
s/\bblip_archive_entry_metadata\b/blar_entry_metadata/g
s/\bblip_archive_entry_xattrs\b/blar_entry_xattrs/g
s/\bblip_archive_entry_container_type\b/blar_entry_container_type/g
s/\bblip_archive_entry_zip_comp\b/blar_entry_zip_comp/g
s/\bblip_archive_entry_pdf_offset\b/blar_entry_pdf_offset/g
s/\bblip_archive_entry_pdf_length\b/blar_entry_pdf_length/g
s/\bblip_archive_entry_jxl_source\b/blar_entry_jxl_source/g
s/\bblip_zip_/blar_zip_/g
s/\bblip_pdf_/blar_pdf_/g
s/\bblip_is_pdf\b/blar_is_pdf/g
s/\bblip_is_zip\b/blar_is_zip/g
s/\bblip_is_wav\b/blar_is_wav/g
s/\bblip_is_aiff\b/blar_is_aiff/g
s/\bblip_is_fits\b/blar_is_fits/g
s/\bblip_is_dicom\b/blar_is_dicom/g
s/\bblip_is_nifti\b/blar_is_nifti/g
s/\bblip_is_gz\b/blar_is_gz/g
s/\bblip_expand_file\b/blar_expand_file/g
s/\bblip_collapse_container\b/blar_collapse_container/g
s/\bblip_wav_to_flac\b/blar_wav_to_flac/g
s/\bblip_flac_to_wav\b/blar_flac_to_wav/g
s/\bblip_aiff_to_flac\b/blar_aiff_to_flac/g
s/\bblip_flac_to_aiff\b/blar_flac_to_aiff/g
s/\bblip_fits_parse\b/blar_fits_parse/g
s/\bblip_dicom_parse\b/blar_dicom_parse/g
s/\bblip_detect_codec\b/blar_detect_codec/g
s/\bblip_zlib_/blar_zlib_/g
s/\bblip_gz_/blar_gz_/g
s/\bblip_free_xattrs\b/blar_free_xattrs/g
'

find src tests -type f \( -name "*.zig" -o -name "*.c" -o -name "*.h" -o -name "*.sh" \) \
  -exec sed -i '' "$SED_SCRIPT" {} \;

# Verify no stray archive-specific blip_* symbols remain
grep -rn "blip_archive_\|blip_zip_\|blip_pdf_\|blip_expand_file\|blip_collapse_container\|blip_is_pdf\|blip_is_zip\|blip_is_wav\|blip_is_aiff\|blip_is_fits\|blip_is_dicom\|blip_is_nifti\|blip_is_gz\|blip_zlib_\|blip_gz_\|blip_wav_to_flac\|blip_flac_to_wav\|blip_aiff_to_flac\|blip_flac_to_aiff\|blip_fits_parse\|blip_dicom_parse\|blip_detect_codec\|blip_free_xattrs" src tests || echo "rename clean"
```

Expected: "rename clean."

- [ ] **Step 3: Trim `lib.zig` to keep only blar-side exports**

Open `src/lib.zig`. The exports to KEEP (now all renamed to `blar_*`):
- `blar_create*`, `blar_file_*`, `blar_verify*`
- `blar_entry_*`, `blar_zip_*`, `blar_pdf_*`
- `blar_is_*` (codec sniffers)
- `blar_expand_file`, `blar_collapse_container`
- `blar_wav_to_flac` etc., `blar_fits_parse`, `blar_dicom_parse`
- `blar_detect_codec`, `blar_zlib_*`, `blar_gz_*`
- `blar_free_xattrs`

The exports to REMOVE (now provided by BLIP dep):
- `blip_encode`, `blip_decode`, `blip_is_sentinel`, `blip_encoded_size`
- `blip_peek*`, `blip_poke`, `blip_container_*`
- `blip_to_json`, `blip_from_json`
- `blip_decode_printable_binary`, `blip_encode_printable_binary`
- `blip_is_compressed`, `blip_is_encrypted`
- `blip_compress_container`, `blip_decompress_container`
- `blip_encrypt_container`, `blip_decrypt_container`
- `blip_segment_*`, `blip_xxhash64`
- `blip_normalize_path`
- `blip_free`, `blip_free_content`
- `blip_error_string`

Use `mcp__codescan__replace_lines` for each removed function. Verify each deletion compiles before the next:
```bash
nix develop -c zig build 2>&1 | grep -E "error:" | grep -v "Unrecognized C flag" | head
```

If errors mention undefined symbols (e.g., `mini_blar`, `expansion_mod`), those imports also need removal in `src/lib.zig`. Adjust until the build is clean.

- [ ] **Step 4: Add a `blar_error_string`**

In `src/lib.zig`, add:
```zig
export fn blar_error_string(error_code: i32) callconv(.c) [*:0]const u8 {
    return switch (error_code) {
        // Archive-specific error codes (move from BLIP's blip_error_string).
        // ZIP, PDF, JXL, encryption, codec expansion errors.
        -33 => "invalid zip file",
        -34 => "encrypted zip not supported",
        -35 => "ZIP64 archive not supported",
        -36 => "ZIP feature not supported",
        -37 => "invalid PDF",
        -38 => "JXL encode failed",
        -39 => "JXL decode failed",
        -40 => "invalid image/audio format",
        -41 => "PDF FlateDecode error",
        -42 => "PDF xref stream error",
        // … plus any other archive-side codes
        else => @ptrCast(blip_error_string(error_code)),  // fall through to BLIP
    };
}
```

The exact code → string mappings are in the original `blip_error_string` (now in BLIP's `lib.zig`). Move the blar-specific cases here. Verify against BLIP's `blip_error_string` to make sure you've moved exactly the archive-side codes.

In `src/blar.h`, declare:
```c
const char *blar_error_string(int32_t error_code);
```

Update C callers in `src/blar.c` to call `blar_error_string` for blar-side error codes; calls to `blip_error_string` from `<blip.h>` (the dep) still work for BLIP-side codes.

- [ ] **Step 5: Verify the build**

```bash
nix develop -c zig build -Doptimize=ReleaseFast 2>&1 | tail -3
```

Expected: build success.

If C linker errors mention undefined `blip_*` symbols (e.g., `_blip_segment_chunk` undefined), make sure `blar.linkLibrary(blip_dep.artifact("blip"))` is in `build.zig` for every executable that depends on libblip.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore(split): rename blip.h to blar.h; rename FFI symbols to blar_*"
```

### Task 2.5: Run the full archive test suite, fix any failures

- [ ] **Step 1: Run Zig unit tests**

```bash
nix develop -c zig build test --summary all 2>&1 | grep -E "Build Summary|tests passed|test failed"
```

- [ ] **Step 2: Run the CLI test suite**

```bash
./test 2>&1 | tail -10
```

Expected: all archive-side tests pass (blar, segmentation, compression, encryption, container expansion, PDF, PNG, streaming, explode/implode).

- [ ] **Step 3: Fix any failures**

Common likely failures:
- **Missing imports of `blip` module** → in the failing `.zig` file, change `@import("blip.zig")` to `@import("blip")` and ensure the build uses the BLIP module.
- **Missing C headers** → in `build.zig`, ensure `blar.addIncludePath(blip_dep.path("src"))` for files including `blip.h` from the dep.
- **Test fixtures missing** → if a test references a sample file (e.g., `tests/fixtures/something.blar`), that fixture should still be in this repo. If not, regenerate from a known-good source.
- **Stale imports of removed types** → e.g., `mini_blar.FileEntry`. The replacement is to use the equivalent type from the BLIP-side dict module: `blip.dict_mod.<Type>` if applicable, or define a local archive-specific type in `src/archive_types.zig`.
- **`./test` references `tests/peek_test.sh` etc.** that no longer exist → edit the master `./test` script to remove those.

- [ ] **Step 4: Verify benchmarks still work**

```bash
./bm 2>&1 | tail -10
```

Note: archive-creation benchmarks should still produce numbers; varint benchmarks have moved to BLIP.

- [ ] **Step 5: Push and verify Garnix CI**

```bash
git push origin yolo
sleep 5
curl -s "https://garnix.io/api/badges/pmarreck/blar?branch=yolo" | head -1
```

Expected: green build status.

- [ ] **Step 6: Tag**

```bash
git tag v3.0.0
git push origin v3.0.0
```

### Task 2.6: Update top-level docs

- [ ] **Step 1: README.md**

Rewrite as "blar: the BLAR archive format and tool, built on BLIP." Cross-reference:
- BLIP: `https://github.com/pmarreck/BLIP`
- mini_blar: `https://github.com/pmarreck/mini_blar`

- [ ] **Step 2: PROJECT_OVERVIEW.md**

Update for blar-only scope. Define the BLAR format, CLI surface, and codec expansion.

- [ ] **Step 3: CLAUDE.md**

Trim to blar-only context. Drop varint/LP-envelope-level discussion (those are BLIP concerns).

- [ ] **Step 4: CODE_MINIMAP.md**

Regenerate from the trimmed `src/` tree. Document each file's purpose. Drop entries for moved files.

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "docs(split): blar top-level docs"
git push origin yolo
```

## Acceptance criteria (Phase 2)

A successful completion of Phase 2 means:
1. ✅ `pmarreck/blar` repo exists on GitHub with full pre-split git history retained
2. ✅ `flake.nix`, `build.zig`, `./test`, `./build` all self-contained and working
3. ✅ blar consumes BLIP via `build.zig.zon` + flake input (NOT via vendored copies)
4. ✅ Garnix CI green on yolo
5. ✅ Tagged `v3.0.0`
6. ✅ All FFI symbols moved to blar use `blar_*` prefix; only BLIP-side symbols (provided by the dep) use `blip_*`
7. ✅ C header is `src/blar.h` (renamed from `src/blip.h`); all C callers `#include "blar.h"`
8. ✅ All archive-side tests green
9. ✅ Top-level docs (README, PROJECT_OVERVIEW, CLAUDE.md, CODE_MINIMAP) reflect blar-only scope and cross-reference BLIP and mini_blar

## Open questions

- (none — every decision in the plan has a recommendation. If a recommendation turns out to be wrong, push back via Peter rather than guessing.)

## Post-v3.0.0 follow-ups (out of Phase 2 scope)

- [ ] **Blarchiver: multi-window support** — let the user spawn additional archiving windows so multiple ops can run in parallel. Each window owns its own archive context, progress state, and document. Reported by Peter 2026-05-05.
- [ ] **Blarchiver: Stop/Abort button** — surface a cancel control during long-running create/extract ops. Must clean up after itself: close the partially-written archive, remove any temp spill files, free the in-flight Zig allocations. Likely needs a cancellation token threaded through `blar_gui_create`/`blar_gui_extract` and into the streaming pipeline. Reported by Peter 2026-05-05.

## Glossary

- **blar**: this project. The BLAR archive format, CLI, GUI, codec expansion.
- **BLIP**: the upstream dep at `pmarreck/BLIP`. Provides the varint encoding, LP envelope mechanic, generic containers (ARRAY, DICT, UTF8, DATA, MAP), SEGMENT primitive, peek/poke navigation, and per-container compression/encryption attributes.
- **mini_blar**: the sister project at `pmarreck/mini_blar`. A constrained subset of blar's format, with its own independent impl. blar does NOT depend on mini_blar.
- **yolo**: the main branch. Never `main`/`master`.
- **Sigil**: an "overlong" BLIP encoding with L=1 and value < 128. Reserved bytes `0x81 0xNN`. blar uses TYPE sigils to distinguish FILE/DIR containers.
- **LP envelope**: a BLIP container's wire format — Length + sorted Attributes + payload.
- **Container types**: enum of 0-127 values stored in the TYPE attribute. blar adds/uses FILE=5, DIR=7. The generic ones (ARRAY, DICT, UTF8, DATA, MAP, SEGMENT) come from BLIP.
