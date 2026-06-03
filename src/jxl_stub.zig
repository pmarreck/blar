//! JXL stub — mirrors jxl.zig's public API surface but performs no libjxl
//! calls and, crucially, contains no `@cImport` of the libjxl headers. Selected
//! in place of jxl.zig when the `enable_image` build option is false, so that
//! consumers which only need BLIP's container/compression API (e.g. difz) can
//! depend on blar without pulling in libjxl / libjxl_threads or their headers.
//!
//! Mirrors the established `compression_stub.zig` pattern. All transcoding
//! entry points fail fast with `error.ImageSupportDisabled`; every external
//! call site handles JXL errors with a catch-all (`catch null`/`continue`/
//! `return …`), so the extra error variant is safe.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const JxlError = error{
    EmptyInput,
    InvalidJpeg,
    InvalidPixelData,
    JxlEncoderCreateFailed,
    JxlEncoderConfigFailed,
    JxlEncodeFailed,
    JxlDecoderCreateFailed,
    JxlDecoderConfigFailed,
    JxlDecodeFailed,
    ImageSupportDisabled,
};

/// Pixel format descriptor — identical layout to jxl.zig's so callers that
/// construct/read `PixelFormat` compile unchanged regardless of which module
/// `enable_image` selects.
pub const PixelFormat = struct {
    width: u32,
    height: u32,
    num_channels: u32,
    bits_per_sample: u32,
};

/// Pure byte check — no libjxl needed, so it stays a real implementation
/// (matches jxl.zig: JPEG SOI marker FF D8).
pub fn isJpegData(buf: []const u8) bool {
    return buf.len >= 2 and buf[0] == 0xFF and buf[1] == 0xD8;
}

pub fn jpegToJxl(_: Allocator, _: []const u8) (JxlError || Allocator.Error)![]u8 {
    return error.ImageSupportDisabled;
}

pub fn jxlToJpeg(_: Allocator, _: []const u8) (JxlError || Allocator.Error)![]u8 {
    return error.ImageSupportDisabled;
}

pub fn pixelsToJxl(_: Allocator, _: []const u8, _: PixelFormat) (JxlError || Allocator.Error)![]u8 {
    return error.ImageSupportDisabled;
}

pub fn jxlToPixels(_: Allocator, _: []const u8, _: *PixelFormat) (JxlError || Allocator.Error)![]u8 {
    return error.ImageSupportDisabled;
}
