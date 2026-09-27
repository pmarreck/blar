# Repository reconciliation, 2026-09-27

This account was reconstructed from Git history, file comparisons, scoped
project memories, and the current conversation. It is not a recovered memory
of the June implementation session.

## Purpose of the apparent unfinished code

The four changed code/build files added `enable_image=false`, allowing consumers
such as difz to omit libjxl headers and libraries while retaining zlib for
PNG/ZIP deflate emission. All four matched both published feature commits
byte-for-byte before reconciliation:

- `14fbf3f5fa1613e58f9dd35cece1d573be71d7f7`: remote `yolo`, committed June 24.
- `26212c756da444374642dcdd54d6431e20122bf9`: local `yolo` and remote
  `thelio/blar-image-opt-and-spec`, committed July 2.

The latter descends from `2cac815`, which adds `BLAR_ARCHIVE_SPEC.md`. Remote
`yolo` instead branched from its parent `b8be537`. Their source code agrees;
the branch-tip trees differed in the specification and an obsolete jj link.
The checkout was detached at `2cac815`, making the already-published feature
appear uncommitted. Reflog entries record old jj exports; jj is no longer used.
The old `worktree-xattr-support` branch is already an ancestor of `yolo`.

Both feature commit messages report 255 default-mode tests passed. They supply
no corresponding disabled-image test result. Treat that number as historical
reported evidence, not a new test run.

## Transcript search

Claude's project directory contained project memories but no conversation
transcript. The cited legacy session was not found locally. Codex's recovered
blar history begins with the September 24 initialization and ACK; the original
June implementation conversation was not recovered. Commit author dates are
not reliable conversation dates: the feature commits retain a June 2 author
date but have June 24 and July 2 committer dates.

## Confirmed decisions in this conversation

- Preserve the intentional deletion of `jj_cheatsheet.md` and
  `ZIG_0.15_TO_0.16_MIGRATION.md`; Zig 0.16 is established and jj is abandoned.
- Reconcile published branches without rewriting history and leave a clean
  working tree on `yolo`.
- Establish canonical intent and file-purpose notes.
- Center the purpose on recompressing files' internally compressed data and
  reconstructing their original format on extraction.
- Acknowledge PowerArchiver prior art without treating it as invalidating blar.
- Continue useful recompression despite difficult exact DEFLATE reconstruction;
  make the limitation clear to people compressing affected files, especially
  when forensic byte identity matters. Warnings remain follow-up work.

## Preserved context

The old split plan is retained verbatim in `2026-05-04-split-plan.md`. Its
unchecked steps are historical claims to audit, not evidence that the split
has yet to happen. Purpose and terminology from `PROJECT_OVERVIEW.md` moved to
`INTENT.md` and `TERMINOLOGY.md`; architecture and toolchain status moved to the
updated code map and README. The former overview remains recoverable in Git.

## Validation findings during reconciliation

The native Zig suite passed 255 tests and the sandboxed Nix Zig check passed.
The full shell suite exposed older environment assumptions: Python fixture
creation was unavailable, macOS-only `md5` commands were missing, and the local
`dd` safety wrapper refused the corruption fixture's overwrite. The last issue
left the archive unchanged; it was not evidence of an integrity-check failure.
Running in the Nix environment, comparing SHA-256 values, and asserting that
mutation occurred restored the CLI corruption test (25 CLI tests passed).
Python is supplied temporarily to run existing fixtures; replacement remains
queued rather than introducing a permanent Python project dependency.

A separate installed-package test failed because Nix's CLI had a nonexistent
ELF interpreter on NixOS. The package now sets the loader to the pinned Nix
linker on Linux and runs that test during installation. The master test runner
also checks the installed artifact, preserves build failures, counts Zig tests,
and prints full failed-suite output instead of hiding all but the final lines.

CI target evaluation selected `packages.x86_64-linux.default` and
`checks.x86_64-linux.default`. During setup, the installed Mechatron client did
not support the documented `provision` command, and GitHub hook inspection
returned HTTP 401. These limit webhook administration; they do not establish
whether an existing hook can deliver the next push.

Final local validation on 2026-09-27 passed the optimized package build and
installed-artifact check, 584 checks through
`nix shell --inputs-from . nixpkgs#python3 -c ./test`, and
`nix build .#checks.x86_64-linux.default --no-link`. The test suite included
255 Zig tests. Documentation changed afterward only to record these results.
No archiver-core source files were changed during reconciliation. The safety
snapshot is retained in Git stash and `/tmp/blar-reconcile.p2IXOq`; the feature
itself is also preserved in the published commits above.
