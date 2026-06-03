const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Optimization mode",
    ) orelse .ReleaseFast;

    const enable_compression = b.option(
        bool,
        "enable_compression",
        "Enable compression support (requires z7z, bzip2z, lz4, zstd). Default: true.",
    ) orelse true;

    const enable_flac = b.option(
        bool,
        "enable_flac",
        "Enable FLAC audio codec support (WAV/AIFF container expansion). Default: true.",
    ) orelse true;

    // When false, blar is built without libjxl (JPEG↔JXL / pixel↔JXL transcode).
    // The jxl.zig module — and its `@cImport` of the libjxl headers — is replaced
    // by jxl_stub.zig, and libjxl/libjxl_threads are not linked. zlib is NOT
    // affected (deflate_emit.zig needs it for PNG/ZIP regardless). Lets consumers
    // that only want BLIP compression (e.g. difz) avoid the libjxl C++ dep tree.
    const enable_image = b.option(
        bool,
        "enable_image",
        "Enable JXL image transcode support (requires libjxl). Default: true.",
    ) orelse true;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_compression", enable_compression);
    build_options.addOption(bool, "enable_flac", enable_flac);
    build_options.addOption(bool, "enable_image", enable_image);

    // printable-binary module (vendored) — needed by static lib for peek FFI
    const pb_module = b.createModule(.{
        .root_source_file = b.path("vendor/printable_binary/printable_binary.zig"),
        .target = target,
        .optimize = optimize,
    });

    // BLIP dep — provides Zig module `blip`, static `libblip.a`, and `blip.h`.
    const blip_dep = b.dependency("blip", .{
        .target = target,
        .optimize = optimize,
    });
    const blip_module = blip_dep.module("blip");
    const blip_lib = blip_dep.artifact("blip");
    const blip_include = blip_dep.path("src");

    // Compression dependencies — lazy, only fetched when enable_compression is true
    const z7z_dep = if (enable_compression) b.lazyDependency("z7z", .{
        .target = target,
        .optimize = optimize,
    }) else null;
    const z7z_module = if (z7z_dep) |dep| dep.module("z7z") else null;

    const bzip2z_dep = if (enable_compression) b.lazyDependency("bzip2z", .{
        .target = target,
        .optimize = optimize,
    }) else null;
    const bzip2z_module = if (bzip2z_dep) |dep| dep.module("bzip2z") else null;

    const lz4_dep = if (enable_compression) b.lazyDependency("lz4", .{
        .target = target,
        .optimize = optimize,
    }) else null;
    const lz4_lib = if (lz4_dep) |dep| dep.artifact("lz4") else null;

    const zstdz_dep = if (enable_compression) b.lazyDependency("zstdz", .{
        .target = target,
        .optimize = optimize,
    }) else null;
    const zstdz_lib = if (zstdz_dep) |dep| dep.artifact("zstd") else null;

    // FLAC dependency — lazy, only fetched when enable_flac is true
    const flac_dep = if (enable_flac) b.lazyDependency("flac", .{
        .target = target,
        .optimize = optimize,
    }) else null;
    const flac_lib = if (flac_dep) |dep| dep.artifact("flac") else null;

    // progrez — progress bar (C library)
    const progrez_dep = b.dependency("progrez", .{
        .target = target,
        .optimize = optimize,
    });
    const progrez_lib = progrez_dep.artifact("progrez");

    // libmagic — MIME-type detection
    const magic_dep = b.dependency("libmagic", .{
        .target = target,
        .optimize = optimize,
    });
    const magic_lib = magic_dep.artifact("magic");

    // libjxl system library (paths from -D options or pkg-config / flake.nix)
    const jxl_include_path = b.option([]const u8, "jxl-include-path", "Path to libjxl headers");
    const jxl_lib_path = b.option([]const u8, "jxl-lib-path", "Path to libjxl libraries");
    // zlib system library — separate path from libjxl on NixOS so that
    // explicit -target builds (e.g. tests) can still find libz / zlib.h.
    const zlib_include_path = b.option([]const u8, "zlib-include-path", "Path to zlib headers (zlib.h)");
    const zlib_lib_path = b.option([]const u8, "zlib-lib-path", "Path to zlib libraries");

    // Helpers — attach codec deps to a module.
    //
    // zlib is required by deflate_emit.zig (PNG/ZIP deflate emission) regardless
    // of image support, so it is attached unconditionally via addZlibSupport.
    // libjxl is only needed for JXL transcode and is gated behind enable_image.
    const addZlibSupport = struct {
        fn apply(
            module: *std.Build.Module,
            z_inc: ?[]const u8,
            z_lib: ?[]const u8,
        ) void {
            if (z_inc) |zi| module.addSystemIncludePath(.{ .cwd_relative = zi });
            if (z_lib) |zl| module.addLibraryPath(.{ .cwd_relative = zl });
            module.linkSystemLibrary("z", .{});
        }
    }.apply;
    const addJxlSupport = struct {
        fn apply(
            module: *std.Build.Module,
            inc_path: ?[]const u8,
            lib_path: ?[]const u8,
        ) void {
            if (inc_path) |inc| module.addSystemIncludePath(.{ .cwd_relative = inc });
            if (lib_path) |lib| module.addLibraryPath(.{ .cwd_relative = lib });
            module.linkSystemLibrary("jxl", .{});
            module.linkSystemLibrary("jxl_threads", .{});
        }
    }.apply;

    const addCompressionSupport = struct {
        fn apply(
            module: *std.Build.Module,
            z7z_mod: ?*std.Build.Module,
            bzip2z_mod: ?*std.Build.Module,
            lz4: ?*std.Build.Step.Compile,
            zstdz: ?*std.Build.Step.Compile,
        ) void {
            if (z7z_mod) |m| module.addImport("z7z", m);
            if (bzip2z_mod) |m| module.addImport("bzip2z", m);
            if (lz4) |lib| module.linkLibrary(lib);
            if (zstdz) |lib| module.linkLibrary(lib);
        }
    }.apply;

    const addFlacSupport = struct {
        fn apply(module: *std.Build.Module, flac: ?*std.Build.Step.Compile) void {
            if (flac) |lib| module.linkLibrary(lib);
        }
    }.apply;

    // Static library — blar's C FFI surface.
    const static_lib = b.addLibrary(.{
        .name = "blar",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "blip", .module = blip_module },
                .{ .name = "printable_binary", .module = pb_module },
            },
        }),
    });
    static_lib.root_module.addOptions("build_options", build_options);
    addZlibSupport(static_lib.root_module, zlib_include_path, zlib_lib_path);
    if (enable_image) addJxlSupport(static_lib.root_module, jxl_include_path, jxl_lib_path);
    if (enable_compression) {
        addCompressionSupport(static_lib.root_module, z7z_module, bzip2z_module, lz4_lib, zstdz_lib);
    }
    if (enable_flac) {
        addFlacSupport(static_lib.root_module, flac_lib);
    }
    static_lib.root_module.linkLibrary(blip_lib);
    if (b.option(bool, "emit-lib-llvm-ir", "Emit LLVM IR for the static library") orelse false) {
        const ir_install = b.addInstallFile(static_lib.getEmittedLlvmIr(), "blar-lib.ll");
        b.getInstallStep().dependOn(&ir_install.step);
    }
    b.installArtifact(static_lib);

    // Public Zig module — consumers like zdiff call
    // `b.dependency("blar", ...).module("blar")` and expect to `@import("blar")`
    // and access `blar.core`, `blar.compression_mod`, etc. Re-export the same
    // root source + dep wiring as the static lib.
    const blar_module = b.addModule("blar", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "blip", .module = blip_module },
            .{ .name = "printable_binary", .module = pb_module },
        },
    });
    blar_module.addOptions("build_options", build_options);
    addZlibSupport(blar_module, zlib_include_path, zlib_lib_path);
    if (enable_image) addJxlSupport(blar_module, jxl_include_path, jxl_lib_path);
    if (enable_compression) {
        addCompressionSupport(blar_module, z7z_module, bzip2z_module, lz4_lib, zstdz_lib);
    }
    if (enable_flac) {
        addFlacSupport(blar_module, flac_lib);
    }
    blar_module.linkLibrary(blip_lib);

    // blar CLI executable — C program that links against the static lib + blip lib.
    const blar = b.addExecutable(.{
        .name = "blar",
        .root_module = b.createModule(.{
            .root_source_file = null,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    blar.root_module.addCSourceFile(.{
        .file = b.path("src/blar.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Wpedantic", "-DHAVE_LIBMAGIC" },
    });
    blar.root_module.linkLibrary(static_lib);
    blar.root_module.linkLibrary(blip_lib);
    blar.root_module.linkLibrary(progrez_lib);
    blar.root_module.linkLibrary(magic_lib);
    blar.root_module.addIncludePath(b.path("src"));
    blar.root_module.addIncludePath(blip_include);
    blar.root_module.addIncludePath(progrez_dep.path("include"));
    if (jxl_lib_path) |lib| blar.root_module.addLibraryPath(.{ .cwd_relative = lib });
    b.installArtifact(blar);

    const blar_run_cmd = b.addRunArtifact(blar);
    blar_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| blar_run_cmd.addArgs(args);
    const blar_run_step = b.step("blar", "Run the blar archive CLI");
    blar_run_step.dependOn(&blar_run_cmd.step);

    // printable-binary CLI executable (vendored)
    const pb_exe = b.addExecutable(.{
        .name = "printable-binary",
        .root_module = b.createModule(.{
            .root_source_file = b.path("vendor/printable_binary/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "printable_binary", .module = pb_module },
            },
        }),
    });
    b.installArtifact(pb_exe);

    // FFI tests (exercise lib.zig's C FFI surface via Zig test harness)
    const ffi_test_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "blip", .module = blip_module },
            .{ .name = "printable_binary", .module = pb_module },
        },
    });
    ffi_test_module.addOptions("build_options", build_options);
    addZlibSupport(ffi_test_module, zlib_include_path, zlib_lib_path);
    if (enable_image) addJxlSupport(ffi_test_module, jxl_include_path, jxl_lib_path);
    if (enable_compression) {
        addCompressionSupport(ffi_test_module, z7z_module, bzip2z_module, lz4_lib, zstdz_lib);
    }
    if (enable_flac) {
        addFlacSupport(ffi_test_module, flac_lib);
    }
    const ffi_tests = b.addTest(.{ .root_module = ffi_test_module });
    ffi_tests.root_module.linkLibrary(blip_lib);
    const run_ffi_tests = b.addRunArtifact(ffi_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_ffi_tests.step);

    // install-tests — emit the test binaries into zig-out/bin/ so that
    // CI lanes can patchelf / wrap them before running. Useful for nix
    // sandboxed test runs where libc-linked binaries need their
    // interpreter patched to the nix glibc loader.
    const install_ffi_tests = b.addInstallArtifact(ffi_tests, .{
        .dest_dir = .{ .override = .{ .custom = "tests" } },
        .dest_sub_path = "ffi_tests",
    });
    const install_tests_step = b.step("install-tests", "Build & install test binaries (without running)");
    install_tests_step.dependOn(&install_ffi_tests.step);

    // compile_commands.json — for clangd / clang-tidy
    const cc_gen = CompileCommandsGen.create(b, .{
        .src_include = b.path("src"),
        .blip_include = blip_include,
        .progrez_include = progrez_dep.path("include"),
        .magic_include = magic_dep.path("src"),
    });
    const cc_step = b.step("compile-commands", "Generate compile_commands.json for clang tooling");
    cc_step.dependOn(&cc_gen.step);
}

/// Custom build step that generates compile_commands.json for src/blar.c.
/// Resolves Zig dependency include paths to actual filesystem paths at build time.
const CompileCommandsGen = struct {
    step: std.Build.Step,
    src_include: std.Build.LazyPath,
    blip_include: std.Build.LazyPath,
    progrez_include: std.Build.LazyPath,
    magic_include: std.Build.LazyPath,

    const Options = struct {
        src_include: std.Build.LazyPath,
        blip_include: std.Build.LazyPath,
        progrez_include: std.Build.LazyPath,
        magic_include: std.Build.LazyPath,
    };

    fn create(b: *std.Build, opts: Options) *CompileCommandsGen {
        const self = b.allocator.create(CompileCommandsGen) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "generate compile_commands.json",
                .owner = b,
                .makeFn = make,
            }),
            .src_include = opts.src_include,
            .blip_include = opts.blip_include,
            .progrez_include = opts.progrez_include,
            .magic_include = opts.magic_include,
        };
        opts.src_include.addStepDependencies(&self.step);
        opts.blip_include.addStepDependencies(&self.step);
        opts.progrez_include.addStepDependencies(&self.step);
        opts.magic_include.addStepDependencies(&self.step);
        return self;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const self: *CompileCommandsGen = @fieldParentPtr("step", step);
        const b = step.owner;
        const alloc = b.allocator;

        const project_root = b.build_root.path orelse ".";
        const src_inc = try self.src_include.getPath3(b, step).toString(alloc);
        const blip_inc = try self.blip_include.getPath3(b, step).toString(alloc);
        const progrez_inc = try self.progrez_include.getPath3(b, step).toString(alloc);
        const magic_inc = try self.magic_include.getPath3(b, step).toString(alloc);

        const content = try std.fmt.allocPrint(alloc,
            \\[
            \\  {{
            \\    "directory": "{s}",
            \\    "file": "src/blar.c",
            \\    "arguments": ["cc", "-std=c11", "-Wall", "-Wextra", "-Wpedantic", "-DHAVE_LIBMAGIC", "-I{s}", "-I{s}", "-I{s}", "-I{s}", "src/blar.c"]
            \\  }}
            \\]
            \\
        , .{
            project_root, src_inc, blip_inc, progrez_inc, magic_inc,
        });

        const io = b.graph.io;
        const out_path = try std.fs.path.join(alloc, &.{ project_root, "compile_commands.json" });
        var file = try std.Io.Dir.cwd().createFile(io, out_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, content);
    }
};
