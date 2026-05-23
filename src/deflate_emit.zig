//! deflate_emit — single chokepoint for blar's deflate-emission paths.
//!
//! Why this module exists: blar's codecs (PNG, ZIP, PDF) all need to *produce*
//! deflate-encoded byte streams when reconstructing files on extract. Without
//! a single chokepoint, each codec implemented its own deflate path — and at
//! least two of them (png.zig and zip.zig) shipped buggy stored-block
//! placeholders that produced spec-valid but functionally useless output
//! (8–80× bloat on PNGs, lurking time-bomb on ZIPs with deflated entries).
//!
//! The architectural intent: PNG/ZIP/PDF call into this module; the deflate
//! implementation lives here. When `deflate_fingerprint` integration arrives,
//! the body of `zlib()`/`rawDeflate()` gets a `fingerprint: ?Fingerprint`
//! argument and dispatches to fingerprint-specific output for byte-identical
//! reproduction of the original encoder. Call sites in PNG/ZIP/PDF stay put.
//!
//! Today: real zlib via C zlib at `Z_DEFAULT_COMPRESSION`. zlib is already
//! linked transitively via libjxl, so no new build dependency.
//!
//! When fingerprint integration arrives, this module also gains a `Framing`
//! enum at the call site and threads `fingerprint_id` through.

const std = @import("std");
const Allocator = std.mem.Allocator;

const c_zlib = @cImport(@cInclude("zlib.h"));

pub const DeflateError = error{
    DeflateFailed,
    OutOfMemory,
};

/// Emit a **zlib-framed** deflate stream (`78 9c ...` + Adler-32 trailer).
/// Used by PNG IDAT reconstruction, PDF FlateDecode streams.
///
/// TODO(deflate_fingerprint): accept `fingerprint: ?u16` and dispatch to
/// fingerprint-specific encoder when known; default-level zlib otherwise.
pub fn zlib(allocator: Allocator, data: []const u8) DeflateError![]u8 {
    const bound = c_zlib.compressBound(@intCast(data.len));
    const buf = try allocator.alloc(u8, bound);
    errdefer allocator.free(buf);

    var dest_len: c_zlib.uLongf = bound;
    const rc = c_zlib.compress2(
        buf.ptr,
        &dest_len,
        data.ptr,
        @intCast(data.len),
        c_zlib.Z_DEFAULT_COMPRESSION,
    );
    if (rc != c_zlib.Z_OK) return error.DeflateFailed;

    const result_len: usize = @intCast(dest_len);
    if (result_len < buf.len) {
        return allocator.realloc(buf, result_len) catch buf[0..result_len];
    }
    return buf[0..result_len];
}

/// Emit a **raw deflate** stream (no zlib framing, no Adler-32).
/// Used by ZIP entries (compression method 8 = DEFLATE).
///
/// TODO(deflate_fingerprint): same `fingerprint` plumbing as `zlib()`.
pub fn rawDeflate(allocator: Allocator, data: []const u8) DeflateError![]u8 {
    var stream: c_zlib.z_stream = std.mem.zeroes(c_zlib.z_stream);

    // deflateInit2 with negative windowBits suppresses zlib framing.
    // -15 = max window size, raw deflate.
    const rc_init = c_zlib.deflateInit2_(
        &stream,
        c_zlib.Z_DEFAULT_COMPRESSION,
        c_zlib.Z_DEFLATED,
        -15, // negative => raw deflate, no zlib framing
        8, // memLevel default
        c_zlib.Z_DEFAULT_STRATEGY,
        c_zlib.ZLIB_VERSION,
        @intCast(@sizeOf(c_zlib.z_stream)),
    );
    if (rc_init != c_zlib.Z_OK) return error.DeflateFailed;
    defer _ = c_zlib.deflateEnd(&stream);

    const bound = c_zlib.deflateBound(&stream, @intCast(data.len));
    const buf = try allocator.alloc(u8, bound);
    errdefer allocator.free(buf);

    stream.next_in = @constCast(data.ptr);
    stream.avail_in = @intCast(data.len);
    stream.next_out = buf.ptr;
    stream.avail_out = @intCast(buf.len);

    const rc = c_zlib.deflate(&stream, c_zlib.Z_FINISH);
    if (rc != c_zlib.Z_STREAM_END) return error.DeflateFailed;

    const result_len: usize = @intCast(buf.len - stream.avail_out);
    if (result_len < buf.len) {
        return allocator.realloc(buf, result_len) catch buf[0..result_len];
    }
    return buf[0..result_len];
}

// ─── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "zlib() produces real-compressed output, not stored blocks" {
    // All-zeros input is the canonical "deeply compressible" case — stored
    // blocks would output ~input.len+overhead; real deflate compresses to
    // a few dozen bytes. We assert *smaller than input* (which stored blocks
    // can never achieve due to header overhead) plus the zlib FLG byte not
    // being 0x01 (which is the precise stored-block-only marker we used to
    // emit).
    var pattern: [4096]u8 = [_]u8{0} ** 4096;

    const out = try zlib(testing.allocator, &pattern);
    defer testing.allocator.free(out);

    // zlib framing: first 2 bytes are CMF + FLG. CMF=0x78 for deflate+32K window.
    // FLG=0x01 = no compression (stored-block path; the bug we're guarding against).
    // FLG=0x9c = default compression, FLG=0xda = best compression. Either is OK.
    try testing.expectEqual(@as(u8, 0x78), out[0]);
    try testing.expect(out[1] != 0x01); // NOT a stored-block stream

    // Real compression of all-zeros should shrink dramatically; stored blocks
    // can never shrink because they have 5-byte headers per 65KB run.
    try testing.expect(out.len < pattern.len);
}

test "rawDeflate() compresses repeating data well, no zlib framing" {
    var pattern: [4096]u8 = [_]u8{0} ** 4096;

    const out = try rawDeflate(testing.allocator, &pattern);
    defer testing.allocator.free(out);

    // Raw deflate has no 0x78 0x9c zlib header. First byte is the
    // deflate block header (BFINAL + BTYPE). For real compressed output
    // it should NOT be a stored-block header.
    // BTYPE values: 0=stored, 1=fixed Huffman, 2=dynamic Huffman.
    // Stored blocks start with bits BFINAL=1, BTYPE=00 → first byte low 3
    // bits = 0b001 = 0x01. Real compression uses BTYPE != 0.
    const block_header_low3 = out[0] & 0x07;
    try testing.expect(block_header_low3 != 0x01); // not a final-stored-block

    try testing.expect(out.len < pattern.len);
}

test "zlib() roundtrip decodes correctly" {
    var pattern: [1024]u8 = undefined;
    for (&pattern, 0..) |*b, i| b.* = @truncate((i * 7) % 251);

    const compressed = try zlib(testing.allocator, &pattern);
    defer testing.allocator.free(compressed);

    // Decode via std.compress.flate
    const flate = std.compress.flate;
    var source_reader = std.Io.Reader.fixed(compressed);
    var empty_buf: [0]u8 = .{};
    var decompress_state = flate.Decompress.init(&source_reader, .zlib, &empty_buf);
    const decoded = try decompress_state.reader.allocRemaining(testing.allocator, .unlimited);
    defer testing.allocator.free(decoded);

    try testing.expectEqualSlices(u8, &pattern, decoded);
}

test "rawDeflate() roundtrip decodes correctly" {
    var pattern: [1024]u8 = undefined;
    for (&pattern, 0..) |*b, i| b.* = @truncate((i * 13) % 241);

    const compressed = try rawDeflate(testing.allocator, &pattern);
    defer testing.allocator.free(compressed);

    const flate = std.compress.flate;
    var source_reader = std.Io.Reader.fixed(compressed);
    var empty_buf: [0]u8 = .{};
    var decompress_state = flate.Decompress.init(&source_reader, .raw, &empty_buf);
    const decoded = try decompress_state.reader.allocRemaining(testing.allocator, .unlimited);
    defer testing.allocator.free(decoded);

    try testing.expectEqualSlices(u8, &pattern, decoded);
}
