# BLAR Archive Format

A deterministic, integrity-verified **archive format** (a compact tar replacement) built on the [BLIP wire format](https://github.com/pmarreck/BLIP/blob/yolo/BLIP_WIRE_SPEC.md). This document specifies the *archive application* layer: the FILE and DIR container types, the archive envelope, metadata key registries, Merkle directory hashing, and archive-specific compression/encryption defaults.

**Author:** Peter Marreck
**Version:** 1.0 (2026-07-02)
**Depends on:** BLIP Wire Format v3.1 (which depends on BLIP Spec v1.2)

> **Provenance.** This spec was split out of the former `BLIP/BLIP_CONTAINER_SPEC.md` (v3.0, 2026-07-02): the generic wire vocabulary (LP envelope, ARRAY/DICT/MAP/UTF8/DATA/RAW, SEGMENT, the optional COMP/CSUM/ENC attribute framework) stayed in BLIP as the wire spec; everything archive-specific moved here. See the wire spec for all primitives referenced below (container type IDs, attribute sigils, key-ordering rule, ARRAY/DICT layout, streaming writes, printable-binary text transport).

## Overview

A BLAR archive is a tree of files and directories serialized as nested BLIP containers. It provides, on top of the wire format:

- **Typed file/dir entries** — FILE (type 5) and DIR (type 7) containers.
- **Extensible metadata** — a compact 2-character key registry (path, mode, mtime, uids, xattrs, …).
- **Dual-level integrity** — a per-content DATA hash plus a structural ARRAY hash on every FILE.
- **Merkle directory hashing** — any change to a file's content or metadata propagates up to the root.
- **Deterministic output** — path-sorted entries + canonical key order + canonical BLIP encoding.
- **Archive-specific compression/encryption defaults** layered on the wire format's optional COMP/ENC attributes.

## Archive-Specific Container Types

### File (type 5)

A container representing a file. Uses **ARRAY layout** (see wire spec §Array) but with the FILE type ID (5). Always contains 2 or 3 elements.

```
┌──────────────────────────────────────────────────────────────────┐
│ Type:    FILE (5)                                               │
│ Length:  BLIP(total)                                            │
│ Value:   (ARRAY structure — index offset, data, index, hash)     │
│                                                                  │
│ Elements (ARRAY layout):                                         │
│   [0]: DICT (metadata) — required keys: pa, md, mt               │
│        optional keys: ct, bt, ui, gi, un, gn                     │
│   [1]: DATA — file content with embedded xxHash64                │
│   [2]: DICT (extended forks, optional)                           │
│        keys: "rf" → RAW (resource fork), xattr names → RAW       │
│                                                                  │
│ Trailing INDEX + xxHash64 (covers everything including metadata) │
└──────────────────────────────────────────────────────────────────┘
```

**Two checksums for free:** the DATA hash (element 1) covers content only; the FILE ARRAY hash covers everything (metadata + content + forks). No explicit content-hash key is needed — hashes are structural.

**Metadata keys (element 0 DICT):**

| Key | Type | Description | Required? |
|-----|------|-------------|-----------|
| `bt` | RAW 8B i64 LE | birthtime / creation time (ns since epoch) | When available |
| `ct` | RAW 8B i64 LE | ctime / inode change time (ns since epoch) | When available (Unix) |
| `gi` | RAW 4B u32 LE | Numeric group ID | When available |
| `gn` | UTF8 | Group name string | When available |
| `md` | RAW 2B u16 LE | POSIX permission bits | Required |
| `mt` | RAW 8B i64 LE | mtime (ns since epoch) | Required |
| `pa` | UTF8 | Relative path (normalized) | Required |
| `ui` | RAW 4B u32 LE | Numeric user ID | When available |
| `un` | UTF8 | Username string | When available |

Keys are in canonical byte sort order (see wire spec §Key Ordering): `bt < ct < gi < gn < md < mt < pa < ui < un`.

**Path normalization:**
- Forward slashes only (`/`), never backslashes.
- No leading slash (relative to archive root).
- No `.` or `..` components.
- UTF-8 encoded, NFC normalized.
- Example: `src/core/main.zig`.

**Extended forks (element 2, optional):** present only when the file has a resource fork or extended attributes. `"rf"` → RAW resource-fork data (macOS); xattr names as-is → RAW xattr values. On extraction to non-macOS, the resource fork is written as an AppleDouble file (`._originalname`).

### Directory (type 7)

A specialized DICT (see wire spec §Dictionary) representing a directory. Uses 2-character lowercase key names for compactness and carries a Merkle hash of its children.

```
┌──────────────────────────────────────────────────────────────┐
│ Type:    DIR (7)                                             │
│ Length:  BLIP(total)                                         │
│ Value:   (DICT structure — index, data, hash)                │
│ Required keys: pa, xh                                        │
│ Optional keys: bt, ct, gi, gn, md, mt, ui, un, xa           │
└──────────────────────────────────────────────────────────────┘
```

**DIR key table:**

| Key | Type | Description | Required? |
|-----|------|-------------|-----------|
| `bt` | RAW 8B i64 LE | birthtime / creation time (ns since epoch) | When available |
| `ct` | RAW 8B i64 LE | ctime / inode change time (ns since epoch) | When available |
| `gi` | RAW 4B u32 LE | Numeric group ID | When available |
| `gn` | UTF8 | Group name string | When available |
| `md` | RAW 2B u16 LE | POSIX permission bits | When available |
| `mt` | RAW 8B i64 LE | mtime (ns since epoch) | When available |
| `pa` | UTF8 | Relative path (normalized) | Required |
| `ui` | RAW 4B u32 LE | Numeric user ID | When available |
| `un` | UTF8 | Username string | When available |
| `xa` | DICT | Extended attributes (xattr name → RAW value) | Optional |
| `xh` | RAW 8B | Merkle hash | Required |

**Merkle hash algorithm.** The `xh` value for a DIR entry is computed from its direct children:

1. Collect the trailing 8-byte xxHash64 from each direct child's container:
   - FILE children → the ARRAY hash (last 8 bytes of the FILE container).
   - DIR children → the DICT hash (last 8 bytes of the DIR container).
2. Sort children by path.
3. Concatenate these 8-byte hashes in sorted-path order.
4. Compute `xxHash64(child_0_hash || child_1_hash || … || child_N_hash)` with seed 0.

This produces a bottom-up hash tree where any change to a file's content OR metadata propagates up through all ancestor directory hashes to the root. Verifying the root directory's Merkle hash transitively verifies every file and subdirectory; individual subtrees can be verified independently.

## Archive Format

A complete archive is a top-level **ARRAY** container:

```
Archive (ARRAY):
  Element 0: RAW containing magic bytes: "BLIP" + version byte (0x01)
  Element 1: ARRAY (body) containing:
    Element 0: DIR  { pa: "src", xh: [Merkle hash], md: 0o755, mt: … }
    Element 1: FILE [metadata DICT {pa: "src/main.zig", md: 0o644, mt: …},
                      DATA [content + xxHash64]]
    …
    Element N-1: FILE or DIR { … }
```

The body array may contain both FILE and DIR entries. Archives without DIR entries are valid — directories are then implicit from file paths.

**Magic identification:** the first bytes of any archive are:
```
0x81 0x01       ← ARRAY type sentinel
BLIP(length)    ← total archive size
BLIP(idx_off)   ← index offset (padded BLIP for streaming, normal otherwise)
0x81 0x04       ← RAW type sentinel (element 0)
0x08            ← RAW length: 8 (2+1+5)
0x42 0x4C 0x49 0x50 0x01  ← "BLIP" + version 1
```

A parser identifies a BLAR archive by checking for the ARRAY sentinel at byte 0, then verifying the first element is a RAW container starting with `"BLIP"`.

**Body element ordering:** entries SHOULD be sorted lexicographically by path for deterministic archives. Parsers MUST NOT assume sorted order — use the index for random access.

**Whole-archive integrity:** the outer ARRAY's trailing xxHash64 covers the entire archive (all files, all metadata, the index). A single 8-byte comparison verifies the whole thing.

## Nesting Examples

### Minimal archive with one file

```
ARRAY                                           ← top-level archive
├── RAW "BLIP\x01"                              ← magic + version
└── ARRAY                                       ← body
    └── FILE (ARRAY layout, type 5)             ← single file
        ├── [0] DICT (metadata)                 ← keys in canonical byte order
        │   ├── "md" → RAW [2 bytes, 0o644]
        │   ├── "mt" → RAW [8 bytes, ns since epoch]
        │   └── "pa" → UTF8 "hello.txt"
        └── [1] DATA                            ← content + embedded xxHash64
            └── "Hello, world!\n" + [8B hash]
```

### Archive with directories

```
ARRAY                                           ← top-level archive
├── RAW "BLIP\x01"
└── ARRAY                                       ← body
    ├── DIR (DICT layout, type 7)               ← directory entry
    │   ├── "md" → RAW [2 bytes, 0o755]
    │   ├── "mt" → RAW [8 bytes, nanoseconds]
    │   ├── "pa" → UTF8 "src"
    │   └── "xh" → RAW [8 bytes, Merkle hash]
    ├── FILE (ARRAY layout, type 5)
    │   ├── [0] DICT { md: 0o644, mt: …, pa: "src/lib.zig" }
    │   └── [1] DATA [file contents + hash]
    └── FILE (ARRAY layout, type 5)
        ├── [0] DICT { md: 0o644, mt: …, pa: "src/main.zig" }
        └── [1] DATA [file contents + hash]
```

The DIR entry's `xh` is `xxHash64(file_hash_lib || file_hash_main)` — a Merkle hash of children's ARRAY hashes, concatenated in path-sorted order.

### Archive with extended metadata and forks

```
ARRAY                                           ← top-level archive
├── RAW "BLIP\x01"
└── ARRAY                                       ← body
    ├── FILE (ARRAY layout, type 5)
    │   ├── [0] DICT (metadata)
    │   │   ├── "gi" → RAW [4 bytes, gid]
    │   │   ├── "gn" → UTF8 "staff"
    │   │   ├── "md" → RAW [2 bytes, 0o644]
    │   │   ├── "mt" → RAW [8 bytes, ns since epoch]
    │   │   ├── "pa" → UTF8 "README.md"
    │   │   ├── "ui" → RAW [4 bytes, uid]
    │   │   └── "un" → UTF8 "peter"
    │   └── [1] DATA [content + hash]
    └── FILE (ARRAY layout, type 5)
        ├── [0] DICT { md: 0o755, mt: …, pa: "icon.icns", un: "peter" }
        ├── [1] DATA [content + hash]
        └── [2] DICT (forks)                    ← extended forks
            ├── "rf" → RAW [resource fork data]
            └── "user.comment" → RAW [xattr value]
```

## Encoding Process

### Writing an archive (in-memory)

When the full archive is built in memory and serialized once, all values are known before any bytes are emitted — no padded BLIPs needed.

```
1. Sort files by path (for deterministic output)
2. Serialize magic element: RAW("BLIP\x01")
3. For each file:
   a. Build metadata DICT (element 0): 2-char keys in canonical order
   b. Build DATA container (element 1): content bytes + xxHash64 suffix
   c. Optionally build forks DICT (element 2): resource fork, xattrs
   d. Serialize FILE as ARRAY-layout with FILE type (5)
   e. Record FILE's position for body array index
4. For each directory:
   a. Compute Merkle hash from children's ARRAY/DICT hashes
   b. Build DIR DICT with 2-char keys (pa, xh, md, mt, …)
5. Build body ARRAY: index offset (normal BLIP), data section, index, xxHash64
6. Build outer ARRAY: index offset (normal BLIP), magic + body, index, xxHash64
```

### Writing an archive (streaming)

When writing to a stream where seeking back is possible but re-emitting the whole container is prohibitive, use padded BLIPs for index-offset fields (see wire spec §Streaming Writes).

```
1. Sort files by path
2. Emit outer ARRAY type + padded Length BLIP (budget for total size)
3. Emit outer ARRAY index offset as padded BLIP (e.g., 12-byte budget)
4. Emit magic element: RAW("BLIP\x01"), record its position
5. Emit body ARRAY type + padded Length BLIP
6. Emit body ARRAY index offset as padded BLIP
7. For each file: build in memory (FILE containers are small), record position
8. Emit body ARRAY index (N, element offsets) + xxHash64
9. Seek back, backfill body ARRAY index offset and Length
10. Emit outer ARRAY index (2, element offsets) + xxHash64
11. Seek back, backfill outer ARRAY index offset and Length
```

If a padded BLIP's budget is exceeded, use the indirect overflow mechanism (see wire spec §Scratch Pool). A 12-byte budget covers offsets up to 2^64, making overflow astronomically unlikely.

### Reading an archive

```
1. Verify outer ARRAY sentinel; read Length → total archive size
2. Optionally verify xxHash64: hash [0..Length-8], compare with [Length-8..Length]
3. Read index offset (consuming padding + PAD_END if padded) → outer index
4. Element 0 offset → verify magic ("BLIP\x01")
5. Element 1 offset → body ARRAY → read body index (count N + offsets)
6. For element K: jump to offset K, check container type:
   - FILE (5): parse as ARRAY; element 0 = metadata DICT (read "pa"), element 1 = DATA
   - DIR (7): parse as DICT; read "pa" for path
```

### Extracting a single file by path

```
1. Parse outer ARRAY → find body ARRAY (element 1)
2. Parse body ARRAY index → all N element offsets
3. For each element: check type; read "pa"; compare with target;
   on FILE match, element 1 is DATA → content (data_len = value_len - 8)
```

For frequent lookups, cache the path→element mapping after the first scan.

## Compression & Encryption (archive defaults)

The wire format defines COMP/CSUM/ENC as optional attributes (see wire spec). The archive layer applies them as follows:

**Compression granularity** — because COMP is an LP attribute on any container:
- **Per-file** (COMP on each FILE/DATA) — preserves O(1) random access to individual files.
- **Solid** (COMP on a parent ARRAY) — compresses all children as one stream for better ratios, at the cost of full decompression to access any child.
- **Grouped** — organize files into sub-arrays (e.g. by content type), compress each independently — solid ratios within groups while keeping O(1) access at the group level.

**Defaults:** blar uses **LZMA2** (COMP id 1) as its default codec. Encryption uses AEAD (AES-256-GCM or ChaCha20-Poly1305) with Argon2id (m=64 MiB, t=3, p=4) or PBKDF2-SHA256 (600k iterations) key derivation, per the wire spec's ENC registry. Serialization order is compress → encrypt → checksum; read order reverses it.

## Human-Readable Representation (archive ↔ JSON)

blar ships `archiveToJson` / `jsonToArchive` (`src/json_serde.zig`): an archive-specialized JSON codec that renders paths, ISO-8601 timestamps, and octal permission modes for readability, and parses them back to a wire buffer for round-tripping and test-data authoring. This builds on (and specializes) the generic container↔JSON correspondence defined in the BLIP wire spec §Human-Readable Representation.

## Size Budget

For a typical case (200 files averaging 50KB each, ~10MB total content):

```
Per-file overhead (FILE as ARRAY with metadata DICT + DATA):
  FILE ARRAY shell:   2 (type) + 3 (length) = 5 bytes
  FILE index offset:  ~3 bytes (BLIP)
  Metadata DICT:      ~5 (shell) + ~3 (idx offset) + ~80 (pa+md+mt)
                      + ~30 (index) + 8 (hash) ≈ 126 bytes
  DATA container:     2 (type) + 3 (length) + content + 8 (xxHash64) = 13 + content
  FILE index:         ~10 bytes (count + 2 element offsets)
  FILE hash:          8 bytes
  Total per file:     ~165 bytes overhead (+ content)

Body array:  200 element offsets ~600 bytes + 8 hash
Outer array: 2 element offsets ~8 bytes + 8 hash

Total overhead:  ~165 × 200 + 600 + 16 ≈ 33.6 KB
Content:         10 MB
Overhead ratio:  0.33%     (compare tar: 200 × 1024 = 200 KB, 2%)
```

## Comparison with tar

| Aspect | tar | BLAR Archive |
|--------|-----|----------------|
| Determinism | Format-dependent (GNU/BSD/POSIX differ) | Guaranteed by spec |
| Random access | Sequential scan only | O(1) via index tables |
| Per-file overhead | 512B header + padding to 512B | ~165 bytes (with metadata) |
| Integrity | None built-in | xxHash64 per array/dict + Merkle dir tree |
| Metadata | Fixed set | Extensible key-value pairs |
| Nesting | Flat | Recursive |
| Streaming write | Yes | Yes (padded BLIP backfill) |
| Streaming read | Yes | Yes (ignore index, read TLVs) |
| Platform encoding | ASCII (POSIX) or UTF-8 (pax) | UTF-8 only |
| Typed values | No | Yes (UTF8, RAW, ARRAY, DICT, MAP, FILE, DIR, DATA) |
| Compression | External (tar.gz, tar.zst) | Built-in LZMA2 via COMP; per-container granularity |
| Encryption | None built-in | Built-in AEAD via ENC attribute |
| Introspection | `tar tf` lists files | `peek` navigates every container, key, and hash |
| JSON interchange | No equivalent | `to-json`/`from-json` round-trip |
| Text transport | Binary-only; requires base64 | printable-binary: copy-pasteable through any text channel |

## Security Considerations

The generic parsing safeguards (recursive-depth limits, length/index validation, duplicate-key rejection, padded-BLIP bounds checks, ENC/AEAD notes) are specified in the [BLIP wire spec §Security Considerations](https://github.com/pmarreck/BLIP/blob/yolo/BLIP_WIRE_SPEC.md). Archive-specific additions:

1. **Path traversal.** Paths MUST be normalized (no leading `/`, no `.`/`..`). Extractors MUST reject or sanitize entries whose normalized path escapes the extraction root.
2. **Symlink targets.** Reject absolute or `../`-escaping symlink targets on extraction.
3. **Merkle authentication scope.** The Merkle tree detects accidental corruption and unintended modification; it is not a cryptographic signature. For authenticity use the ENC attribute (AEAD) or a future SIG attribute.
4. **Resource-fork / xattr on extraction.** Writing forks/xattrs to disk MUST respect the target filesystem's capabilities and MUST NOT allow a crafted xattr name to escape the target file.

## License

MIT — see [LICENSE](LICENSE).
