# Terminology

| Term | Meaning |
|---|---|
| blar | This archive library, CLI, and current GUI implementation. |
| BLAR | The archive format built from BLIP containers; see `BLAR_ARCHIVE_SPEC.md`. |
| BLIP | The upstream length-prefixed integer encoding, generic container envelope, and generic container library. |
| mini_blar | A separate, constrained implementation of a subset of BLAR. It is not a blar dependency. |
| LP envelope | A BLIP container's length, sorted attributes, and payload. |
| Sigil | A reserved overlong BLIP encoding of the form `0x81 0xNN` for values below 128. |
| FILE / DIR | Archive-specific container semantics; FILE has type ID 5 and DIR has type ID 7. |
| Container expansion | Decomposing a recognized file format into components for compression, then reconstructing it during extraction. |
| Byte identity | The reconstructed file has exactly the original bytes, including encoding and metadata representation. |
| Content identity | Decoded content is preserved, but the reconstructed file's bytes can differ. |
| Segmentation | Splitting an archive into numbered transport files with BLIP SEGMENT framing for later reassembly. |
| Solid compression | Compression on the containing body rather than each file; reading one member can require decompressing the whole body. |
| Printable-binary | The separate reversible byte-to-Unicode encoding used to carry binary data in text. |
| yolo | The primary branch of this repository. |
