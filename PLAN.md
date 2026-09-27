# PLAN

Current work is ordered below. The original split checklist is preserved in docs/plan_context/2026-05-04-split-plan.md.

## Repository reconciliation

- [x] Reconcile published work from 26212c7 and 14fbf3f onto yolo, retaining the specification and intentional obsolete-link deletions (done 2026-09-27 14:42 EDT).
- [x] Establish INTENT.md around internal recompression, reconstruction limits, and PowerArchiver prior art; migrate the overview and refresh file-purpose notes (done 2026-09-27 14:42 EDT).
- [x] Verify the optimized package, all 584 master-suite checks, and the sandboxed Nix test target (done 2026-09-27 14:42 EDT).
- [x] Push reconciled yolo, verify remote equality and clean status, and confirm Mechatron admits eef68d5 (done 2026-09-27 14:44 EDT).

## Fixture generator port

- [x] Port fixtures and optional audit/benchmark helpers to LuaJIT; pass all 681 master-suite checks without Python and all 97 sandboxed helper checks (done 2026-09-27 15:07 EDT).

## Follow-up work

- [ ] Measure and document per-format byte identity, including PNG/ZIP/PDF deflate reconstruction; disclose content-only preservation (context: INTENT.md).
- [ ] Add focused regression coverage for enable_image=false and verify downstream consumers can omit libjxl.
- [ ] Audit the historical split checklist against shipped code before treating its unchecked entries as remaining work (context: docs/plan_context/2026-05-04-split-plan.md).
- [ ] Add independent macOS GUI windows for concurrent archive operations (context: docs/plan_context/2026-05-04-split-plan.md).
- [ ] Add cancellation to GUI archive operations with resource and partial-output cleanup (context: docs/plan_context/2026-05-04-split-plan.md).

- [ ] Warn before recompressing formats whose original DEFLATE bytes cannot be guaranteed; distinguish content preservation from forensic byte identity.
