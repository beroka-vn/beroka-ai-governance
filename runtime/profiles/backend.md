# Backend Repository

- The repository owns its machine-readable API, schema, and event contracts;
  those team-local artifacts may remain private.
- Canonical capability pages use the reviewed Backend Capability Registry and
  globally unique Folder hierarchy.
- One capability page owns one immutable Capability ID and links the exact
  repository artifact/version/commit. A consumer-facing cross-team handoff is
  a self-contained Confluence contract snapshot, including the public API or
  WebSocket detail needed by Frontend without Backend repository access.
- Jira and Confluence writes remain inside the configured routing unless an
  active integration profile authorizes an exact counterpart.
- Backend classification alone does not declare a Frontend dependency.
