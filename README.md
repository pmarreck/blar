# blar — BLAR archive format and tool

[![built with garnix](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fgarnix.io%2Fapi%2Fbadges%2Fpmarreck%2Fblar)](https://garnix.io/repo/pmarreck/blar)

`blar` is a deterministic, integrity-verified, structurally introspectable archive format with a `tar`-like CLI. Think `tar`, but with BLAKE3-128 outer + xxHash64 inner integrity, O(1) random access via end-of-container index tables, built-in LZMA2 compression and AEAD encryption, structural inspection via path expressions (`peek`/`poke`), JSON round-tripping (`to-json`/`from-json`), printable-binary text representation, and transparent container expansion (PDF, PNG, JPEG-via-JXL, ZIP, tar, gzip, BMP, TGA, TIFF, GIF, WAV/AIFF→FLAC, FITS, DICOM, NIfTI).

The archive format is called **BLAR**. The encoding it builds on is **BLIP** — see [pmarreck/BLIP](https://github.com/pmarreck/BLIP) for the underlying length-prefixed integer encoding and generic container envelope.

Sister project: [pmarreck/mini_blar](https://github.com/pmarreck/mini_blar) — a constrained subset of the BLAR format with its own independent implementation.

## Build

Requires [Nix](https://nixos.org/) with flakes enabled. All dependencies (Zig 0.15.2, libFLAC, libjxl, hyperfine) are provided hermetically.

```bash
./test           # run tests
./build          # build (ReleaseFast)
./build --debug  # build (Debug)
./bm             # run benchmarks
```

## Usage

### Smart defaults (no subcommand needed)

```bash
blar myproject/              # create archive (detects directory)
blar archive.blar            # extract (detects .blar extension)
blar -z myproject/           # create with compression
```

### Explicit commands

```bash
blar create -o archive.blar myproject/        # archive a directory tree
blar create myproject                         # default output: myproject.blar
blar create -o archive.blar file1 file2       # archive individual files
blar list archive.blar                        # list entries
blar extract archive.blar -C output_dir/      # extract restoring perms+structure
blar verify archive.blar                      # BLAKE3-128 outer + per-file + Merkle
blar info archive.blar                        # metadata (counts, sizes)
blar cat archive.blar path/to/file.txt        # print single file to stdout
blar peek archive.blar "[1][0]" --type        # navigate structure
blar poke archive.blar "[1][0][1]" --value x  # modify a leaf value
blar to-json archive.blar | jq ...            # JSON interchange
blar from-json -o b.blar < input.json
```

### Tar-style shortcuts (hyphen optional)

```bash
blar cf archive.blar myproject/   # create
blar tf archive.blar              # list
blar xf archive.blar              # extract
blar Vf archive.blar              # verify
blar If archive.blar              # info
blar pf archive.blar file.txt     # cat (print)
blar kf archive.blar "[1][0]"     # peek
blar Kf archive.blar "[1][0][1]"  # poke
blar jf archive.blar              # to-json
blar Jf input.json -o out.blar    # from-json
```

### Segmentation

```bash
blar create --segment-size 100M -o archive.blar myproject/   # split during create
blar create --segment-count 4   -o archive.blar myproject/   # equal-sized N segments
blar split archive.blar --size 100M                          # split existing archive
blar join  archive.blar.000 archive.blar.001 ...             # rejoin segments
blar reassemble archive.blar.000                             # autodetect tail
```

`list`, `extract`, `verify`, `info` all auto-detect segment files.

## Inspecting archives (`peek`)

Navigate the binary structure with jq-like path expressions. Every container, metadata key, and hash is addressable.

```bash
blar peek archive.blar "[1][0]" --type            # FILE
blar peek archive.blar "[1][0].count"             # 2
blar peek archive.blar "[1][0].hash"              # a1b2c3d4e5f6a7b8
blar peek archive.blar "[1][0][0][pa]"            # file path
blar peek archive.blar "[1][0][0][md]"            # 0644 (mode as octal)
blar peek archive.blar "[1][0][0][mt]"            # 2026-02-24T10:30:00.123456789Z
blar peek archive.blar "[1][0][1]" --raw          # raw file content
blar peek archive.blar "[1][0][1]" --hex          # 0x68656c6c6f...
blar peek archive.blar ".hash"                    # archive's stored checksum
```

Archive structure: `ARRAY[DATA(magic), ARRAY[FILE[DICT{metadata}, DATA{content}], ...]]`.

`--raw` writes raw bytes (printable-binary-encoded with stderr warning if stdout is a tty). `--hex` shows payload hex for leaves and container checksum for aggregates. `--json` emits JSON with printable-binary identity check on strings. `--type` is shorthand for `.type`.

## Modifying archives (`poke`)

Same path syntax as `peek`, but *sets* values. The entire archive is re-serialized with all hashes, offsets, and index tables recomputed automatically.

```bash
echo -n "new content" | blar poke archive.blar "[1][0][1]"
blar poke archive.blar "[1][0][0][pa]" --value "renamed.txt"   # rename
blar poke archive.blar "[1][0][1]" -i data.bin                 # read from file
blar poke archive.blar "[1][0][1]" --value "x" -o modified.blar   # write to new file
blar poke archive.blar "[1][0][1]" --value "x" --backup           # .bak before overwrite
```

## JSON interchange (`to-json` / `from-json`)

Convert any archive to JSON, manipulate with `jq`, convert back. Byte-identical round-tripping for uncompressed/unencrypted archives — same files in produces same bytes out.

```bash
blar to-json archive.blar | jq '.entries[].path'

# Modify content
blar to-json a.blar \
  | jq '(.entries[] | select(.path=="hello.txt")).content = "new"' \
  | blar from-json -o b.blar

# Add / remove / rename / chmod via jq edits, all the usual moves.

# Re-apply compression and/or encryption when materializing
BLAR_PASSWORD=secret blar to-json encrypted.blar \
  | BLAR_PASSWORD=secret blar from-json -z -e -o b.blar
```

Binary content is encoded via printable-binary in JSON strings. All hashes, offsets, and index tables recompute on `from-json`. `to-json` decompresses and decrypts transparently — `from-json -z`/`-e` re-applies them.

## Encryption

Per-container AEAD encryption as an LP attribute. Encryption is applied after compression and before checksumming.

- **Ciphers**: AES-256-GCM (default, hardware-accelerated), ChaCha20-Poly1305 (constant-time on all platforms)
- **KDF**: Argon2id (default, 64 MiB / 3 iter / parallelism 4), PBKDF2-SHA256 (600,000 iter, portable fallback)

```bash
blar create -e -o secret.blar myproject/                 # AES-256-GCM + Argon2id
blar create -e chacha -o secret.blar myproject/          # ChaCha20-Poly1305
blar create -e --kdf pbkdf2 -o secret.blar myproject/    # PBKDF2 instead
blar create -z -e -o secret.blar myproject/              # compress + encrypt
BLAR_PASSWORD=mysecret blar list secret.blar             # decrypt on read
blar list secret.blar                                    # interactive prompt on stderr
```

A wrong password fails the AEAD tag check — no ambiguity about whether decryption succeeded.

## blar vs tar

| | `blar` | `tar` |
|---|---|---|
| Determinism | Byte-identical output guaranteed by spec | Format-dependent; GNU/BSD/POSIX produce different bytes |
| Integrity | BLAKE3-128 outer + xxHash64 inner + Merkle hashes | None built-in |
| Random access | O(1) via end-of-container index tables | Sequential scan only |
| Per-file overhead | ~165 bytes | 1024 bytes minimum (512-byte aligned) |
| Metadata | Extensible key-value, any container type as value | Fixed header fields (or pax extended) |
| Typed values | UTF8, DATA, ARRAY, DICT, MAP, FILE, DIR | Byte ranges in fixed-width fields |
| Nesting | Recursive | Flat |
| Encryption | Built-in AEAD | None — layer external |
| Compression | Built-in LZMA2 per-container with format-aware expansion | External, whole-archive |
| Introspection | `peek`/`poke` with path expressions | `tar tf` only |
| JSON interop | Full round-trip via `to-json`/`from-json` + `jq` | None |
| Text-safe transport | Printable-binary encoding | Binary only |
| Specification | Single canonical spec | v7, ustar, pax, GNU, BSD — multiple incompatible |

**Where tar wins**: ubiquity. Every Unix system has it.

**Where blar wins**: correctness guarantees, structural transparency, and dramatically smaller archives via container expansion.

## Compression granularity

LP attributes apply to any container, so blar supports the full spectrum:

- **Per-file**: COMP on each FILE/DATA. Preserves O(1) random access.
- **Solid**: COMP on the body ARRAY. Best ratio for similar files; whole-archive decompress to read one file.
- **Grouped**: organize files by content type into sub-arrays, compress each group independently. Different algorithms (or none) per group; e.g. skip COMP for already-compressed video.

```
ARRAY (archive)
├── DATA (magic)
└── DICT (body, keyed by content type)
    ├── "image/png"   → ARRAY [FILE, FILE, ...]   ← COMP=lzma2
    ├── "text/plain"  → ARRAY [FILE, FILE, ...]   ← COMP=lzma2
    └── "video/mp4"   → ARRAY [FILE, FILE, ...]   ← no COMP
```

## Transparent container expansion

`blar` automatically detects and decomposes known file formats during archiving so LZMA2 can compress them effectively. Extraction reconstructs the original file byte-identically. This is transparent — you archive a PDF, you extract a PDF.

| Format | What happens | Notes |
|---|---|---|
| **PDF** | JPEGs → JXL (lossless), zlib streams decompressed, structural shell preserved | byte-identical; up to 70% smaller on text-heavy PDFs |
| **PNG** | Raw pixels → lossless JXL; metadata chunks (tEXt/iCCP/pHYs) preserved | pixel-identical with metadata |
| **ZIP** | Per-entry decompression; structure preserved | byte-identical |
| **gzip** | Decompressed inside; recompressed on extract | content-identical (level/strategy not preserved) |
| **tar** | Decomposed into constituent files; headers preserved as metadata | byte-identical; lets LZMA2 group across tar boundary |
| **BMP/TGA/TIFF** | Raw pixels → JXL; compact header metadata | byte-identical; ~90–97% savings |
| **GIF** | Pure-Zig LZW decoder → JXL pixels; original GIF stored as metadata if smaller | byte-identical |
| **WAV/AIFF** | PCM → FLAC via libFLAC; non-PCM chunks preserved | byte-identical; 50–60% on real audio |
| **FITS / DICOM / NIfTI** | Pixel/voxel data → JXL; text headers / DICOM tags preserved | byte-identical; compressed/encapsulated DICOM left as-is |

Real PDF results:

| PDF | Original | blar (no expand) | blar (expand) | Savings |
|---|---|---|---|---|
| Far Side Vol I (673 JPEGs) | 158 MB | ~155 MB | 121 MB | 23% smaller |
| Slaughterhouse-Five (text-only) | 876 KB | ~840 KB | 780 KB | 16% smaller |
| Beginning Lua Programming | 8.6 MB | ~8.2 MB | 2.5 MB | 70% smaller |

```bash
blar create -z -o archive.blar documents/                       # expand by default
blar create -z --no-expand-containers -o archive.blar docs/     # disable
blar list archive.blar                                          # types: p=PDF, n=PNG, j=JPEG,
                                                                # b=BMP, a=TGA, i=TIFF, f=GIF,
                                                                # w=WAV/AIFF, s=FITS, m=DICOM,
                                                                # g=gzip, t=tar, z=ZIP, d=dir, -=file
```

## C FFI

`blar` is a hexagonal-design app: a pure-Zig core with no I/O, exposed via a C FFI in `src/blar.h`, with a C CLI dogfooding the FFI.

```c
#include "blar.h"

blar_file_entry files[] = {
    { "hello.txt", 9, (uint8_t*)"Hello!\n", 7 },
};
uint8_t *archive;
size_t archive_len;
blar_create(files, 1, /*flags=*/0, &archive, &archive_len);
bool ok = blar_verify(archive, archive_len);
blip_free(archive, archive_len);   /* freer comes from BLIP */
```

The BLIP encoding/container primitives (`blip_encode`, `blip_decode`, `blip_peek`, `blip_poke`, `blip_segment_*`, etc.) are provided by the BLIP dep — `#include <blip.h>` for those.

## License

MIT — see [LICENSE](LICENSE).
