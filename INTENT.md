# blar intent

## Purpose and users

blar is an archiver that re-encodes files' existing internal compression into
more efficient representations, then reconstructs the original file format on
extraction. A PDF, PNG, JPEG, or other compressed file can offer little to a
general-purpose compressor until its internal encoding is unpacked. blar aims
to recover that opportunity without requiring people to change their working
file formats. This is the central purpose Peter reaffirmed on 2026-09-27.

The project provides the BLAR archive format, a command-line archiver, a C API,
and a macOS graphical client. It serves people archiving mixed file trees and
library consumers needing the same operations through a C ABI or Zig module.
Integrity checks and inspectable structure support trust in the reconstruction.

## Prior art

Format-aware recompression has precedent. Peter identified PowerArchiver as
prior art; its [December 2016 Advanced Codec Pack announcement](https://www.powerarchiver.com/2016/12/21/powerarchiver-2017-details-about-advanced-codec-pack-pa-format/)
describes Reflate preprocessing of deflate streams in PDF, Office, PNG, and
other formats. That source establishes a related approach, not a comparison
of reconstruction guarantees or performance against blar.

The project does not depend on claiming invention of this technique. Evaluate
its usefulness through measured compression gains, reconstruction fidelity,
resource costs, portability, and inspectability. Superiority to PowerArchiver
or other implementations remains unmeasured.

## Desired outcomes

- Preserve file contents, directory structure, and supported metadata through
  creation and extraction. Format-aware expansion should improve compression
  while retaining the information needed to reconstruct the original files.
- Produce deterministic archives for identical inputs, ordering, metadata, and
  configuration. Encryption randomness must be accounted for when testing this
  guarantee; independently encrypted archives need not have identical bytes.
- Detect corruption through outer and inner checksums and directory Merkle
  hashes, and reject failed authenticated decryption.
- Support indexed access and structural inspection or editing through
  `peek`/`poke`, plus JSON and printable-binary interchange.
- Allow compression and encryption at container granularity, including per-file,
  solid, and grouped arrangements. Solid compression trades individual access
  for compression ratio.
- Support the CLI on macOS aarch64, Linux aarch64/x86_64, and Windows
  aarch64/x86_64. This is the target platform set, not a claim that every target
  is currently built or tested.

## Scope and boundaries

BLAR archive semantics, FILE/DIR metadata, streaming creation, codec expansion,
the CLI, and the current GUI belong here. The upstream
[BLIP project](https://github.com/pmarreck/BLIP) owns the integer encoding,
generic container envelope, and generic container operations. The independent
[mini_blar project](https://github.com/pmarreck/mini_blar) owns its constrained
archive implementation. Printable-binary remains a separate encoding.

The core architecture is in-memory Zig computation exposed through
`src/blar.h`; the C CLI and Swift GUI exercise that C API. Keep I/O at the
boundary where possible. The current implementation also has streaming I/O and
a process-wide Zig I/O adapter; the architectural goal does not imply those
are already pure functions.

Optional codecs should not force unnecessary dependencies on library consumers.
In particular, `enable_image=false` removes libjxl transcoding and its headers
and libraries; zlib remains necessary for PNG/ZIP deflate emission. The default
retains image support. This decision is recorded in commits `14fbf3f` and
`26212c7`.

## Verification and unresolved guarantees

Use `./build` and `./test` for the normal build and regression suite, and the
corpus audit in [tests/audit/README.md](tests/audit/README.md) for empirical
reconstruction checks. Compare bytes for byte-identity claims, decoded content
for content-identity claims, and measure performance with `./bm`.

Reconstructing the original file format and reconstructing its exact bytes are
different guarantees. Peter confirmed on 2026-09-27 that exact ZIP reconstruction
had proved difficult and that useful recompression should continue with candid
disclosure. Warn people when compressing ZIP, Office documents, PDFs, or other
formats using DEFLATE internally if the original compressed bytes cannot be
guaranteed. Do not present content-equivalent output as forensically identical.

The desired policy is to make this limitation clear when someone chooses to
compress affected files. Such disclosure and its user-interface tests are
follow-up work, not a claim about today's CLI. Retaining original bytes through
an untransformed archive remains relevant when exact preservation is required.

The former overview described byte-identical reconstruction for expanded
formats except gzip. Existing audit documentation identifies PNG and ZIP-based
formats as content-identical only, and synthetic PDF success does not prove
all PDF inputs round-trip identically. Measure reconstruction per format and
input corpus. Byte identity remains valuable where achievable; failure to
reproduce a DEFLATE stream exactly does not invalidate the broader project.

Indexed container access is a design goal. End-to-end file lookup costs and
compressed-container access must be measured separately before advertising a
blanket constant-time guarantee.

## Sources and navigation

This intent was recovered from the tracked `PROJECT_OVERVIEW.md` at `26212c7`,
the archive specification, README, and existing audit documentation. Peter
requested its creation on 2026-09-27. It introduces no license or commercial
release change.

- [Archive specification](BLAR_ARCHIVE_SPEC.md): wire format and metadata.
- [Terminology](TERMINOLOGY.md): project boundaries and format vocabulary.
- [Code map](CODE_MINIMAP.md): implementation and file purposes.
- [Plan](PLAN.md): current work and follow-ups.
