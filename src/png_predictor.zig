//! Shared PNG Paeth predictor, used by both PNG IDAT defiltering (png.zig) and
//! PDF FlateDecode predictor handling (pdf.zig), which reuses PNG predictor
//! semantics per the PDF spec.

/// PNG/TIFF Paeth predictor (RFC 2083 §6.6): returns whichever of the left (a),
/// above (b), or upper-left (c) neighbor is closest to the estimate
/// p = a + b - c, breaking ties toward a then b. Pure function over i16 inputs.
pub fn paethPredictor(a: i16, b: i16, c: i16) u8 {
    const p = a + b - c;
    const pa = @as(u16, @intCast(if (p > a) p - a else a - p));
    const pb = @as(u16, @intCast(if (p > b) p - b else b - p));
    const pc = @as(u16, @intCast(if (p > c) p - c else c - p));
    if (pa <= pb and pa <= pc) return @intCast(@as(u16, @intCast(a)));
    if (pb <= pc) return @intCast(@as(u16, @intCast(b)));
    return @intCast(@as(u16, @intCast(c)));
}

test "paeth predictor picks nearest neighbor" {
    const std = @import("std");
    // p = a+b-c; when all equal, picks a
    try std.testing.expectEqual(@as(u8, 10), paethPredictor(10, 10, 10));
    // classic ordering check
    try std.testing.expectEqual(@as(u8, 2), paethPredictor(2, 3, 4));
}
