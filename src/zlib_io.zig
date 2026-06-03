//! Shared zlib (RFC 1950) decompression used by PNG IDAT and PDF FlateDecode.
//! The decompression body was previously copy-pasted into png.zig and pdf.zig;
//! callers that need a domain-specific error map the generic error.InvalidData
//! at their call site (e.g. png.zig wraps it as PngError.CorruptedData).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Fully zlib-decompress `compressed` into a caller-owned slice. Wraps
/// std.compress.flate.Decompress in .zlib mode. Any malformed/short stream or
/// allocation failure surfaces as error.InvalidData.
pub fn zlibDecompress(allocator: Allocator, compressed: []const u8) ![]u8 {
    const flate = std.compress.flate;
    var source_reader = std.Io.Reader.fixed(compressed);
    var empty_buf: [0]u8 = .{};
    var decompress_state = flate.Decompress.init(&source_reader, .zlib, &empty_buf);
    return decompress_state.reader.allocRemaining(allocator, .unlimited) catch
        return error.InvalidData;
}
