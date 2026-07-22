# Pull Request Template

Use a Conventional Commit PR title: `<type>(<scope>): <imperative subject>`.

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

- Epic Integration Hub:
- Linked Frontend Jira/GitHub issue(s):
- Canonical contract artifact/version/commit:
- Behavior delivered:
- Authentication/permissions:
- Error and edge cases:
- Test environment and sanitized evidence:
- Breaking/migration impact:
- Known limitations/unverified items:
- State before merge: DRAFT | BLOCKED
- Expected state after merge: READY_FOR_FE

Do not copy a contract body into the PR. Link the exact BE artifact/version.
After merge, update the Hub/changelog, set `READY_FOR_FE`, and notify the linked
FE issue; the FE owner acknowledges the exact version.

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
