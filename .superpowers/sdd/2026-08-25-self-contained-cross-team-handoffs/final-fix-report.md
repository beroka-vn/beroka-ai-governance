# Final Fix Wave Report

Date: 2026-08-25

Base: `2aade65e84a63ff4d09b0b296dafb26eb514c4bc`

Scope: the single authorized final fix wave for the 1 Critical and 7 Important
whole-branch review findings. No live Jira or Confluence write, release, push,
PR, or mutation of Confluence page `85360641` was performed.

## Result

All eight blocking findings are addressed with regression coverage and scoped
root-cause changes. Ordinary team-local Jira and Confluence writes retain their
existing behavior. The DRAFT-update minor was not changed: DRAFT remains
create-only and READY remains update-only as required by the approved design.

## Findings closed

1. **Untrusted readback attestation (Critical).** Removed caller-assertion
   comparison as a source of verification. `confluence-handoff-verify` now
   proves read capability only and prints `Readback: CAPABILITY_ONLY`.
   Caller-supplied `--readback-*` assertions fail with
   `HANDOFF_READBACK_REQUIRED` before connector inspection. This CLI has no
   provenance-preserving post-tool hook, so no runtime path emits
   `Readback: VERIFIED`; agents must report unverified and must not report
   READY until a trusted client path directly binds the write receipt and
   subsequent read response.
2. **Legacy/ordinary Cursor bypass.** Cursor now routes new-schema labels,
   readiness claims, opposite BB/BF evidence, legacy handoff plus GitHub
   evidence, and acknowledgment plus Confluence evidence through the governed
   body gate. The exact incident shape no longer falls through to ordinary
   `confluence-write`.
3. **Folder relevance and ancestry.** The ACTIVE Folder supplies a required
   scope/domain/transport triple. Transport must match API-only,
   WebSocket-only, or combined API+WebSocket impact. Every update/read
   capability check requires a reviewed target row whose recorded parent is
   the exact expected Folder; untracked updates and mismatched parents fail
   before connector inspection.
4. **Private intake routing disclosure.** `jira-intake-write` output exposes
   only the receiving profile and Jira project. Opposite private repository
   identity remains internal to routing and was removed from guidance.
5. **Provider direction.** The handoff provider Jira project must match the
   routed team's Jira project. Coverage includes Backend-to-Frontend rejection
   of the wrong provider and the symmetric Frontend-to-Backend positive case.
6. **Per-entry contracts.** Each affected API inventory entry must match one
   complete `API operation` block, and each affected WebSocket inventory entry
   must match one complete `WebSocket contract` block. Duplicate, extra, or
   missing blocks fail validation.
7. **Secret and internal-detail leakage.** The gate now rejects common reusable
   credentials (`client_secret`, password, Basic/Bearer authorization, access
   and refresh tokens, private keys) and internal topic/topology/adapter/provider
   publication claims. Regression examples include every exact reviewer
   example.
8. **Jira acknowledgment isolation.** Cursor classifies plain acknowledgment
   text and opposite-project evidence, and scans every textual value in nested
   tool input for cross-team operations. Team-local Jira input remains on its
   ordinary path.

## TDD evidence

The initial regressions failed before implementation:

- `tests/routing.sh` exposed `Intake target repository` in Jira intake output.
- `tests/cursor-hooks.sh` allowed a plain acknowledgment with a nested GitHub
  value to reach the ordinary Jira/GitHub path.

Additional focused regressions cover no-write verification, the exact legacy
incident, wrong transport and parent ancestry, route/provider mismatch,
multi-inventory mismatch, reusable secrets/internal details, and plain Jira
acknowledgments.

## Verification evidence

Final-tree test evidence:

- `tests/bootstrap.sh`: `Bootstrap onboarding tests: PASS`
- `tests/connectors.sh`: `Connector selection tests: PASS`
- `tests/cursor-hooks.sh`: `PASS: Cursor hook runtime`
- `tests/documentation-architecture.sh`: `Documentation architecture tests: PASS`
- `tests/launcher.sh`: `One-command launcher tests: PASS`
- `tests/release.sh`: `First public release readiness: PASS`
- `tests/routing.sh`: `PASS: routing state`
- `tests/smoke.sh`: `PASS: user-scoped governance commands`
- `sh -n bin/beroka-governance tests/*.sh`: exit 0
- `git diff --check`: exit 0

The first combined full-suite attempt stopped at Cursor after bootstrap and
connector passed: the new ancestry rule correctly rejected the positive
Cursor fixture's synthetic untracked page. The fix was limited to adding a
test-only ACTIVE target row in the cloned test release; production inventory
was not changed. Cursor then passed, and the remaining suites completed in one
continuation without restarting routing.

## Security ruling

The approved design's original caller-supplied readback interface conflicts
with the final Critical finding because local arguments and result files can be
fabricated. The safer final-review ruling supersedes that interface. The
design and normative guidance now explicitly describe capability-only output
and the absence of trusted post-tool proof in this release. This intentionally
leaves READY reporting blocked rather than manufacturing verification.
