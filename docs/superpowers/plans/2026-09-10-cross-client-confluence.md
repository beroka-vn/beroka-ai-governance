# Cross-client Confluence implementation plan

**Goal:** Resolve GitHub #88 through native tool hooks on Codex, Claude and Cursor.
**Design:** Approved in the issue-88 conversation. Reuse the existing content and routing validators. Native pre-tool events supply the actual arguments; post-tool events supply actual write and subsequent read responses. Never accept a caller's body file or readback assertion as execution proof.
**Stack:** Existing POSIX shell, jq and Git. No new dependencies or OAuth transport.

- [x] Add a regression through each client's native pre/post event envelope, with a real pinned test release and simulated connector responses. Run `sh tests/confluence-hooks.sh` and observe missing entrypoint failure.
- [x] Add `confluence-hook CLIENT EVENT` and managed hook installation. Share the existing Confluence preflight with an explicit internal client argument. Keep standalone preflight blocked for untrusted bodies.
- [x] Bind receipts to client, repository, session, tool-call ID and exact arguments. Validate write response and subsequent readback ID, parent, space, version and body; retain unknown/failed readback state without automatically retrying a write.
- [x] Cover ordinary create/update, DRAFT create, READY_FOR_FE update, invalid body, wrong target/account, changed outbound arguments, write failure and readback failure. Preserve existing readiness validation.
- [x] Align runtime instructions and documentation with native hook requirements, including unsupported-host diagnostics and a new-client integration contract.
- [x] Run `scripts/build-cli.sh --check` and all `tests/*.sh`. Record simulated versus live evidence; do not write the reported business page.
