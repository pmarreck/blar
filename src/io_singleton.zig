//! io_singleton.zig — captures `std.Io` once for the blar library/CLI process.
//!
//! blar is a library exposed via a C FFI. Its public surface takes no `io`
//! parameter — all callers (the C CLI in `blar.c`, language bindings, the FFI
//! test harness) call through `export fn` entry points that did not exist in
//! the Zig 0.15 API era and would not naturally carry an `io` argument.
//!
//! Rather than thread `io` through every internal function (which would also
//! mean every FFI export gaining an io parameter — a breaking API change),
//! we install a process-wide lazily-initialised `std.Io.Threaded` and let
//! the few sites that need it (`std.fs.cwd()` replacements, `std.time.Timer`
//! replacements, `argon2.kdf`, `std.crypto.random`) call into this singleton.
//!
//! This is the documented "io singleton shim" pattern from
//! `ZIG_0.15_TO_0.16_MIGRATION.md` (codescan/par2z firsthand notes). The
//! safety guarantee the migration doc warns about ("io stays alive longer
//! than any code that uses it") is satisfied by construction — the io is a
//! process-global with the lifetime of the process.

const std = @import("std");
const builtin = @import("builtin");

var fallback_threaded: ?std.Io.Threaded = null;
var fallback_init_state: std.atomic.Value(u8) = std.atomic.Value(u8).init(0); // 0=uninit, 1=initing, 2=ready

fn getFallbackIo() std.Io {
    while (true) {
        const cur = fallback_init_state.load(.acquire);
        if (cur == 2) return fallback_threaded.?.io();
        if (cur == 0 and fallback_init_state.cmpxchgStrong(0, 1, .acquire, .acquire) == null) {
            // Use c_allocator so spawn / readToEndAlloc / similar paths that
            // allocate internally do not hit Allocator.failing.
            fallback_threaded = std.Io.Threaded.init(std.heap.c_allocator, .{});
            fallback_init_state.store(2, .release);
            return fallback_threaded.?.io();
        }
        std.atomic.spinLoopHint();
    }
}

/// Return the process-wide io (lazily initialised). Always safe to call.
pub fn io() std.Io {
    if (builtin.is_test) return std.testing.io;
    return getFallbackIo();
}
