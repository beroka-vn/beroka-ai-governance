# Native Confluence live validation — 2026-09-10

The maintainer authorized completing the unfinished PPSE documentation for
BB-64 (parent Epic BB-63) as a real publication test before v1.0.16.

## Actual publication

- Page: [PPSE and loan-package selection](https://beroka.atlassian.net/wiki/spaces/Berokaback/pages/90865665)
- Content ID: `90865665`
- Parent: User-API folder `90636305`
- Space: Berokaback, ID `65961986`
- Final observed version: `2`
- Jira remains independent of documentation publication; no readiness or Done
  transition was performed.

Cursor Agent `2026.09.08-6caf4ff` ran the installed native hooks in a fresh
session. It observed the exact space, confirmed no existing child page, and
created one page. The native pre/post hooks recorded the actual request and
returned content ID/version. Initial readback failed because Confluence escaped
intraword underscores in two prose lines (owner and timezone).

After the readback fix at `3680a90`, a new native read verified the original
write receipt, without another create or manual receipt edits. A subsequent
single update removed the duplicated body heading, omitted optional parentId
and spaceId, and inferred their expected values from the preceding native page
read. The new native read verified version 2 and the original hierarchy.
Both sequences returned `READBACK_VERIFIED`; no pending write receipt remained.

The original outbound argument and body hashes remain exact. The readback fix
accepts only escaped intraword underscores in a conservative prose subset.
Code, metadata and other bytes remain exact; unsupported Markdown remains
unverified. Regression coverage includes altered code, URLs, email, math,
multiline labels and ambiguous closing fences. This follows the distinction
between prose escapes and literal code in the
[CommonMark specification](https://spec.commonmark.org/spec).

## Other clients

- Codex CLI `0.154.0`: a fresh session performed a real space read and the native
  hook produced `Confluence space identity observed`. This exposed the native
  `mcp__codex_apps__atlassian_rovo__*` alias, fixed at `b35c7b7`. The CLI reached
  its usage limit before a successful write; Codex write/readback remains
  unverified. Earlier attempts were denied before writing due to the isolated
  test configuration hiding GitHub configuration; the harness was corrected to
  reference the original provider-owned GitHub config without copying tokens.
- Claude Code: live validation was explicitly skipped by the maintainer because
  the account had no remaining usage. Simulated lifecycle coverage is available;
  it is not live-client evidence.

## Candidate and evidence integrity

Validation used detached local candidate checkouts and local annotated tags;
no stable release tag was published as part of testing. The original provider
OAuth stores were reused. Native hosts invoked the configured hook commands;
no caller-supplied hook stdin or manual receipt creation was used as proof.
Temporary hooks were removed after verification, preserving unrelated user
settings. No pending write remained. The temporary configuration records
identifiers and hashes, not credentials.

All eleven local shell suites passed on the final runtime, including native-hook
lifecycle and Markdown regressions; CLI build/syntax and diff checks also passed. Earlier PR #89 and the initial
version-only release preparation passed Ubuntu and macOS CI. The final release
PR must run CI with these live-discovered fixes.

Stable publication still requires either the missing Codex write/readback
validation or an explicit maintainer waiver. The Claude waiver does not imply
that Codex passed.
