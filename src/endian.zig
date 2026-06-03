//! Tiny endian-aware fixed-width integer readers shared across format parsers.
//! These wrap `std.mem.readInt` so call sites read as `readU16LE(buf)` while a
//! single definition lives here instead of being copy-pasted into every parser.

const std = @import("std");

/// Read a little-endian u16 from the first 2 bytes of a slice.
pub fn readU16LE(buf: []const u8) u16 {
    return std.mem.readInt(u16, buf[0..2], .little);
}

/// Read a little-endian u32 from the first 4 bytes of a slice.
pub fn readU32LE(buf: []const u8) u32 {
    return std.mem.readInt(u32, buf[0..4], .little);
}

/// Read a big-endian u16 from the first 2 bytes of a slice.
pub fn readU16BE(buf: []const u8) u16 {
    return std.mem.readInt(u16, buf[0..2], .big);
}

/// Read a big-endian u32 from the first 4 bytes of a slice.
pub fn readU32BE(buf: []const u8) u32 {
    return std.mem.readInt(u32, buf[0..4], .big);
}

test "round-trip endian readers" {
    try std.testing.expectEqual(@as(u16, 0x0201), readU16LE(&[_]u8{ 0x01, 0x02 }));
    try std.testing.expectEqual(@as(u16, 0x0102), readU16BE(&[_]u8{ 0x01, 0x02 }));
    try std.testing.expectEqual(@as(u32, 0x04030201), readU32LE(&[_]u8{ 0x01, 0x02, 0x03, 0x04 }));
    try std.testing.expectEqual(@as(u32, 0x01020304), readU32BE(&[_]u8{ 0x01, 0x02, 0x03, 0x04 }));
}
