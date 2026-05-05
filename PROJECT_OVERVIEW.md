# blar — Project Overview

## What blar is

`blar` is the **BLAR archive format** and its reference CLI / GUI tooling. It is a deterministic, integrity-verified, structurally introspectable archive format with format-aware transparent container expansion. It plays a similar role to `tar` but trades universality for correctness guarantees, random access, and dramatically smaller archives.

The wire format (BLAR) is one application of the **BLIP** length-prefixed integer encoding and generic container envelope, which lives upstream at [pmarreck/BLIP](https://github.com/pmarreck/BLIP).

## What blar is not

- **Not a varint encoding.** That's BLIP — depended on, not redefined here.
- **Not a flat-file mini-archiver.** That's [pmarreck/mini_blar](https://github.com/pmarreck/mini_blar) — a sister project with its own independent implementation of a constrained subset of BLAR.
- **Not a universal interchange format.** It is opinionated and Zig-implemented; interop is via `to-json`/`from-json`, segment files, or its printable-binary text representation.

## Goals

1. **Determinism.** Same inputs (files + caller-controlled order + flags) must produce byte-identical output. Canonical key ordering, canonical BLIP integer encoding, sorted container attributes.
2. **Integrity.** BLAKE3-128 on the outer archive; xxHash64 on inner containers; Merkle hash tree on directory trees so any leaf change propagates to the root.
3. **Random access.** O(1) random access to any container element via end-of-container index tables. No sequential scan to find one file in a million.
4. **Structural transparency.** `peek`/`poke` navigate by path expression — every container, metadata key, and hash is addressable. Archives are not opaque blobs.
5. **Built-in compression and encryption** as LP attributes — per-container granularity, no external tooling required.
6. **Format-aware transparent container expansion** — known file formats (PDF, PNG, ZIP, tar, gzip, BMP/TGA/TIFF, GIF, WAV/AIFF, FITS/DICOM/NIfTI) are decomposed during archiving so LZMA2 can compress them; reconstructed byte-identically on extract.
7. **Text-safe representation** — entire archives can be transmitted through any text channel via printable-binary encoding.
8. **Cross-platform CLI** — Mac aarch64, Linux aarch64/x86_64, Windows aarch64/x86_64. Hexagonal design (Zig core, C FFI, C CLI dogfoods the FFI).

## Architecture

```
   blar CLI (C, in src/blar.c)
            │
            ▼
   C FFI header (src/blar.h)
            │
            ▼
   blar Zig core (src/lib.zig + codecs)   ←── pure logic, no I/O
            │
            └─── consumes ──► BLIP module (external dep, build.zig.zon + flake.nix)

   macOS GUI app (Swift, in macos-app/) ── also calls into C FFI
```

Rules:
- All business logic lives in the Zig core. No I/O.
- The C FFI (`src/blar.h`) is the public API. CLI and GUI call through it.
- Do **not** write a Zig CLI that imports the Zig core directly — bypassing the FFI defeats the dogfooding strategy. Going Zig→C→Zig feels wrong but is intentional.

## Format glossary

- **BLAR** — this archive format. The outer wire envelope is `ARRAY[DATA(magic), ARRAY[FILE | DIR, ...]]` with optional COMP/ENC/CSUM/SIG attributes per container.
- **BLIP** — the upstream length-prefixed integer encoding and generic container envelope. Provides ARRAY, DICT, UTF8, DATA, MAP, SEGMENT, plus the LP envelope mechanic and per-container compression/encryption attributes. Comes from [pmarreck/BLIP](https://github.com/pmarreck/BLIP) as a `build.zig.zon` + flake input.
- **mini_blar** — the sister project at [pmarreck/mini_blar](https://github.com/pmarreck/mini_blar). A constrained subset of the BLAR format with its own independent implementation. blar does **not** depend on mini_blar.
- **LP envelope** — a BLIP container's wire format: `Length + sorted Attributes + payload`.
- **Sigil** — an "overlong" BLIP encoding with L=1 and value < 128 (reserved bytes `0x81 0xNN`). blar uses TYPE sigils to distinguish container types.
- **Container types** — enum 0–127 stored in the TYPE attribute. Generic types (ARRAY, DICT, UTF8, DATA, MAP, SEGMENT) come from BLIP. blar adds **FILE = 5** and **DIR = 7**.
- **Segmentation** — a BLAR archive may be split into N segment files (`*.000`, `*.001`, …) using BLIP's SEGMENT primitive. `blar create --segment-size`, `blar split`, `blar join`, `blar reassemble` operate on these.

## Compression and encryption

- **Compression**: LZMA2 only, applied as a COMP attribute on any container. Per-file, solid, or grouped strategies all fall out of attribute placement — no special "solid block" feature needed.
- **Ciphers**: AES-256-GCM (default) or ChaCha20-Poly1305.
- **KDFs**: Argon2id (default, 64 MiB / 3 iter / parallelism 4) or PBKDF2-SHA256 (600,000 iter, portable fallback).
- **Layering**: write order is *compress → encrypt → checksum*; read order is *verify checksum → decrypt → decompress*.
- **Auth**: AEAD tag mismatch is an unambiguous decryption failure.

## Container expansion targets

PDF · PNG · ZIP · gzip · tar · BMP · TGA · TIFF · GIF · WAV · AIFF · FITS · DICOM · NIfTI. All are byte-identical reconstructions on extract except gzip, which is content-identical (level/strategy not preserved).

## CLI surface

`blar create`, `list`, `extract`, `verify`, `info`, `cat`, `peek`, `poke`, `to-json`, `from-json`, `segment`, `split`, `join`, `reassemble`. Tar-style shortcuts (`cf`, `tf`, `xf`, `Vf`, `If`, `pf`, `kf`, `Kf`, `jf`, `Jf`) accepted.

Smart defaults: bare directory argument → create; bare `.blar` argument → extract.

All arguments accepting paths also accept `-` / `@stdin` / `@stdout` / `@stderr`. Output about output (progress, warnings, metadata) goes to stderr; structured payloads go to stdout (JSON-pipeable).

## Branch and CI

- **Main branch**: `yolo` (across all repos in this set).
- **CI**: Garnix (org-wide). `flake.nix` exposes `packages.default` and `checks.{build, test}`. The badge in `README.md` points at `garnix.io/api/badges/pmarreck/blar`.
- **Cross-platform**: 5 OS/arch combos via `./build_all`. Mac Intel intentionally unsupported (GitHub no longer provides runners).

## Versioning

`v3.0.0` is the first blar release after the BLIP/blar/mini_blar split. The pre-split umbrella history is retained in this repo for continuity. BLIP is consumed by tag (`v3.0.0` → `build.zig.zon`/`flake.nix` inputs).
