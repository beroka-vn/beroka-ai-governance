# Pull Request Template

Use a Conventional Commit PR title: `<type>(<scope>): <imperative subject>`.
This is a team-local GitHub Issue/PR section; GitHub links may remain here, but
consumer-facing cross-team handoff text uses Jira and Confluence only.

```markdown
## Status

- [ ] Draft — implementation/validation is incomplete
- [ ] Ready for review — self-review and evidence are complete

## Traceability

- Jira task:
- GitHub Issue:
- Relevant docs:
- `Closes #<issue-number>`

## Labels

- Type: type:<feature|bug|technical>
- Area: area:<frontend|backend|shared>
- Priority: priority:<p0-p3>

Copy labels from the linked Issue. Ask the human/manager if they are missing or
conflict with Jira.

## Summary

<Outcome delivered and changes used to deliver it>

## Scope

- [ ] Contains only linked Issue scope.
- [ ] Branch contains the correct Issue number.
- [ ] No unrelated cleanup/refactor.

### Changed

- <Changed behavior/module/interface>

### Intentionally unchanged

- <Contract/flow/data/UI intentionally unchanged>

## Impact

- Contract/public API: None | <details>
- Database/schema/data: None | <details>
- Security/permissions: None | <details>
- Runtime/config/deployment: None | <details>
- Documentation: None | <details>
- Frontend impact: None — <reason> | Handoff required

### Documentation change (when documentation is affected)

- Canonical document content ID/path:
- Capability ID:
- Capability Registry reference:
- Sections changed:
- Change class: docs-only | contract-compatible | contract-breaking
- Contract artifact/version/commit: <before → after | N/A>
- Document revision: <before → after | N/A for repository files>
- Additional related Jira items:

Several Jira items may reference the same canonical page; this PR still closes
one primary GitHub Issue and Jira item. Update existing Confluence content by
exact content ID rather than title similarity.

## Frontend evidence (when UI is affected)

- Before:
- After:
- Viewports/browsers:
- Loading/empty/error/permission states:
- Keyboard/accessibility basics:

## Backend evidence (when service/data is affected)

- API/contract compatibility:
- Migration/data behavior:
- Sanitized request/response:
- Rollback behavior:

## BE → FE handoff (when Frontend impact != None)

- Capability ID and Registry reference:
- Epic Integration Hub:
- Provider Jira and consumer Jira:
- Confluence content ID and version:
- Self-contained handoff page:
- FE acknowledgment:
- State before merge: DRAFT | BLOCKED
- Expected state after merge: READY_FOR_FE

Do not place private Backend repository links in the consumer-facing handoff.
After merge, update the self-contained Confluence page and report
`READY_FOR_FE` only after readback; the FE owner acknowledges that exact page
version.

## Validation

| Command/check | Environment | Result | Evidence |
| --- | --- | --- | --- |
| `<exact command>` | `<local/test/staging>` | PASS/FAIL | <summary/link> |

### Manual/runtime smoke

1. <Exact action> → <expected and observed result>

### Not run / Unverified

- <Check/item> — <exact blocker or reason>

Never leave this blank. Write `None` when every required check ran.

## Risk and rollback

- Main risks:
- Rollback/recovery:
- Follow-up issue:

## Review

### Author self-review

- [ ] Diff was reread.
- [ ] Acceptance criteria were checked.
- [ ] Evidence comes from the current commit.
- [ ] `Self-review completed — ready to merge` is recorded.

GitHub does not allow authors to native-approve their own PR. This checklist is
the team record when repository settings permit self-merge.

### Review outcomes

| Reviewer | Human/AI | Commit SHA | Result | Blocking items |
| --- | --- | --- | --- | --- |
| <name> | <Human/AI> | <full SHA> | approve/request changes/comment | <None/details> |

### Human authorization for AI approval/merge

- Required: yes | no
- PR/current full SHA:
- Authorized AI agent/account:
- Allowed action: review only | approve | merge | approve and merge
- Merge method: squash | merge | rebase
- Conditions:
- Authorized by:
- Authorized at with timezone:

Without authorization, AI may only review/comment.

## Merge checklist

- [ ] Acceptance criteria pass.
- [ ] Blocking feedback is resolved or explicitly accepted.
- [ ] Labels match the linked Issue.
- [ ] Current commit was reviewed/authorized.
- [ ] Documentation impact is handled.
- [ ] Required handoff, Hub, linked FE item, and contract version are complete.
- [ ] Handoff can become `READY_FOR_FE` immediately after merge.
- [ ] Merge method is confirmed; prefer squash.
- [ ] Branch will be deleted after merge.
```
