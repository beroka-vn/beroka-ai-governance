# Ví dụ traceability end-to-end

Ví dụ này dùng record giả định để minh họa một outcome được tách thành Jira
items trong hai projects `BB`/`BF`, triển khai trong phạm vi riêng của từng team,
handoff bằng một Confluence contract tự chứa và hoàn tất bằng một Confluence
document.

## 1. Jira task `APP-120`

```markdown
# Hiển thị tổng quan giá trị danh mục

## Objective

Người dùng xem được tổng giá trị và thay đổi trong ngày của danh mục trên
dashboard.

## Context

Dashboard hiện chỉ hiển thị từng tài sản, khiến người dùng phải tự cộng tổng.

## Expected outcome

- Người dùng thấy tổng giá trị danh mục.
- Người dùng thấy giá trị và tỷ lệ thay đổi trong ngày.
- Trạng thái không có tài sản được giải thích rõ ràng.

## Ownership and timeline

- Owner: Product Manager An
- Priority: High
- Sprint: 2026-S15

## Input links

- Product brief: Confluence/APP-PORTFOLIO-OVERVIEW
- Figma: Figma/portfolio-dashboard-v2

## Delivery links

- Delivery Jira: BB-120, BF-87
- Contract handoff: Pending
- Completion document: Pending
```

Jira không chỉ định endpoint, component, file hoặc library.

`APP-120` là coordination item do Product Manager An sở hữu; executable
assignments được từng team theo dõi riêng. Vì vậy assignee gate không reassign
`APP-120`. Nếu team tạo Jira Story/Task/Bug/Feature riêng để Nam hoặc Linh yêu
cầu AI thực thi, Jira item đó phải assign đúng developer trước khi implementation
bắt đầu.

## 2. Issue decomposition

| Jira item | Outcome | Labels | Primary owner | Dependency |
| --- | --- | --- | --- | --- |
| `BB-120` | Cung cấp portfolio summary API | `type:feature`, `area:backend`, `priority:p1` | Nam | Existing holdings/pricing contracts |
| `BF-87` | Hiển thị portfolio summary trên dashboard | `type:feature`, `area:frontend`, `priority:p1` | Linh | Confluence contract từ `BB-120` |

Manager cập nhật coordination item `APP-120`, cross-links `BB-120` và `BF-87`,
và link cả hai tới cùng một Integration Hub.

### Backend Capability Registry

```markdown
| Capability ID | Scope / domain / transport | Canonical Confluence content | Owner / page version |
| --- | --- | --- | --- |
| `PORTFOLIO-SUMMARY` | Derivatives / User / API | Content ID `900001` | Backend / Pending |
```

Registry row là canonical mapping. Page content ID `900001` thuộc ACTIVE Folder
content ID `900002`; Hub và FE Index chỉ tham chiếu exact content ID/version.

### Epic Integration Hub `APP-INTEGRATION-12`

```markdown
# Portfolio summary — Integration Hub

- Backend Epic/Task: BB-120
- Frontend Epic/Task: BF-87
- Coordinator: An

| Canonical handoff | Provider Jira | Handoff state | Consumer Jira | Breaking |
| --- | --- | --- | --- | --- | --- |
| Confluence `900001`, version pending | BB-120 | DRAFT | BF-87 | None |
```

Hub là Epic current-state index. Public contract snapshot nằm đầy đủ trong
Confluence page; Hub chỉ tham chiếu exact content ID/version và không chứa
repository, branch, PR hoặc commit của team cung cấp.

## 3. Backend Issue `#121`

```markdown
# [Feature] Cung cấp portfolio summary API

## Traceability

- Jira task: BB-120; coordination item APP-120
- Product docs: Confluence/APP-PORTFOLIO-OVERVIEW
- Epic Integration Hub: APP-INTEGRATION-12
- Capability ID: PORTFOLIO-SUMMARY
- Capability Registry reference: PORTFOLIO-SUMMARY — Confluence 900001
- Related Jira: BF-87 consumes Confluence handoff content ID 900001

## Classification

- Labels: type:feature, area:backend, priority:p1
- Primary owner: Nam
- Branch: feature/121-portfolio-summary-api
- AI involvement: review

## Objective

Authenticated user nhận được tổng market value, daily change value và daily
change percentage từ portfolio summary endpoint.

## Scope

### In scope

- Add `GET /api/v1/portfolio/summary`.
- Aggregate existing holdings and pricing service results.
- Return an explicit empty-portfolio response.

### Out of scope

- Frontend rendering.
- Changes to pricing or holdings calculation contracts.

## Behavior that must remain unchanged

- Existing holdings endpoints and authorization behavior.
- Price/value precision already defined by the pricing contract.

## Acceptance criteria

- [ ] Endpoint returns `200` with total value and daily change fields.
- [ ] Empty portfolio returns zero values, not `404` or `null` fields.
- [ ] Unauthenticated request remains `401`.
- [ ] Existing holdings API tests remain passing.

## Validation

```bash
pytest tests/api/test_portfolio_summary.py -q
pytest tests/api/test_holdings.py -q
```

Manual smoke: call the endpoint with populated, empty and unauthenticated test
accounts; verify `200`, `200` and `401` respectively.

## BE → FE handoff

- Epic Integration Hub: APP-INTEGRATION-12
- Frontend Jira: BF-87
- Capability ID / Registry reference:
  `PORTFOLIO-SUMMARY` / Confluence content ID `900001`
- Active parent Folder: content ID `900002`
- State: DRAFT
```

## 4. Backend branch và PR `#131`

```text
Branch: feature/121-portfolio-summary-api
Commit: feat(portfolio): add summary endpoint
PR: #131 feat(portfolio): add summary endpoint
Links: BB-120, APP-120, APP-INTEGRATION-12, Closes #121
Labels: type:feature, area:backend, priority:p1
```

Validation evidence trên PR:

```text
pytest tests/api/test_portfolio_summary.py -q
6 passed in 0.42s

pytest tests/api/test_holdings.py -q
14 passed in 0.77s

Manual smoke (local test environment):
- populated account -> 200, expected totals
- empty account -> 200, zero values
- unauthenticated -> 401

Not run / Unverified: None
```

Nam ghi `Self-review completed — ready to merge` trên commit giả định
`1111111111111111111111111111111111111111`.

Manager An yêu cầu AI review nhưng không giao quyền merge:

```text
AI authorization
- PR: #131
- Reviewed commit: 1111111111111111111111111111111111111111
- Agent: claude-review-bot
- Allowed action: approve
- Merge method: squash
- Conditions: approve only if all acceptance criteria and evidence pass
- Authorized by: An
- Authorized at: 2026-07-17T14:00:00+07:00
```

AI đối chiếu issue, diff và evidence, sau đó approve đúng commit. An thực hiện
squash merge. GitHub đóng `#121` qua `Closes #121`.

Sau merge, Nam tạo DRAFT từ exact template, hoàn thiện toàn bộ common/API/no-WS
sections trong chính Confluence page, rồi chạy read-capability preflight. Vì
chưa quan sát đủ write receipt và kết quả read sau đó qua native post-tool hook,
Hub và linked FE Jira chưa nhận record này:

```markdown
Provider Jira: BB-120
Consumer Jira: BF-87
Confluence content ID: 900001
Confluence page version: 3
Parent Folder content ID: 900002
API impact: affected
WebSocket impact: none
Missing sections: None
Readback: CAPABILITY_ONLY — post-tool write/read evidence pending
Proposed state: READY_FOR_FE
Reported readiness: UNVERIFIED
```

Nam không comment record này vào `BF-87`; Linh chưa ghi `ACKNOWLEDGED` cho tới
khi trusted post-tool evidence chứng minh exact Confluence content ID/version.
FE không tự tổng hợp contract từ repository, Issue hoặc PR của Backend.

The remaining recipient-execution example is conditional on this explicit
native trusted proof event; this illustrative record is not live publication evidence:

```text
Trusted post-tool proof event: NATIVE_HOOK_READBACK_VERIFIED
Write receipt and subsequent read response: exact content 900001, parent 900002, version 3, space, and body verified
Readback: VERIFIED
State transition: DRAFT -> READY_FOR_FE
Provider action: comment exact content 900001 version 3 on BF-87
Consumer action: ACKNOWLEDGED exact content 900001 version 3
```

## 5. Frontend Issue `#122`

```markdown
# [Feature] Hiển thị portfolio summary trên dashboard

## Traceability

- Jira task: BF-87; coordination item APP-120
- Design: Figma/portfolio-dashboard-v2
- Epic Integration Hub: APP-INTEGRATION-12
- Capability ID: PORTFOLIO-SUMMARY
- Capability Registry reference: PORTFOLIO-SUMMARY — Confluence 900001 version 3
- Frontend Capability Index: `Portfolio — Capability Index`
- Dependency: Confluence content ID `900001`, version `3`, from BB-120 — ACKNOWLEDGED

## Classification

- Labels: type:feature, area:frontend, priority:p1
- Primary owner: Linh
- Branch: feature/122-portfolio-summary-card
- AI involvement: assist and review

## Objective

Dashboard hiển thị tổng giá trị, thay đổi trong ngày và empty state từ summary
API.

## Scope

### In scope

- Add Portfolio Summary card to the existing dashboard.
- Render loading, populated, empty and API-error states.
- Use the contract delivered by Confluence content ID `900001`, version `3`.

### Out of scope

- Backend calculations.
- Dashboard layout outside the portfolio section.

## Behavior that must remain unchanged

- Existing asset-list interactions and responsive navigation.

## Acceptance criteria

- [ ] Populated state matches approved Figma content and format.
- [ ] Empty portfolio shows guidance instead of blank values.
- [ ] Loading and error states are visible and accessible.
- [ ] Existing asset-list interactions remain passing.

## Validation

```bash
npm test -- PortfolioSummaryCard.test.tsx
npm run build
```

Manual: verify four states at mobile and desktop widths with keyboard navigation.
```

## 6. Frontend branch và PR `#132`

```text
Branch: feature/122-portfolio-summary-card
Commit: feat(portfolio): show dashboard summary
PR: #132 feat(portfolio): show dashboard summary
Links: BF-87, APP-120, APP-INTEGRATION-12, Closes #122, consumes Confluence content 900001 version 3
Labels: type:feature, area:frontend, priority:p1
```

Validation evidence trên PR:

```text
npm test -- PortfolioSummaryCard.test.tsx
8 tests passed

npm run build
Build completed successfully

Manual checks:
- Chrome desktop 1440px: populated/loading/empty/error passed
- Chrome responsive 390px: populated/loading/empty/error passed
- Keyboard focus and screen-reader labels passed
- Before/after screenshots attached

Not run / Unverified: Safari visual check — no Safari environment available;
accepted by An for this initial release.
```

Linh self-review trên commit giả định
`2222222222222222222222222222222222222222`. An yêu cầu AI review và merge:

```text
AI authorization
- PR: #132
- Reviewed commit: 2222222222222222222222222222222222222222
- Agent: gemini-review-bot
- Allowed action: approve and merge
- Merge method: squash
- Conditions: no blocking finding; preserve the documented Safari limitation
- Authorized by: An
- Authorized at: 2026-07-17T15:30:00+07:00
```

AI review current SHA, approve và squash merge theo authorization. GitHub đóng
`#122`. Nếu commit thay đổi sau review, authorization trên không còn hiệu lực.

## 7. Confluence completion document `APP-DOC-45`

```markdown
# APP-120 — Portfolio summary delivered

## Metadata

| Field | Value |
| --- | --- |
| Jira | APP-120, BB-120, BF-87 |
| Owners | An, Nam, Linh |
| Completed at | 2026-07-17T16:00:00+07:00 |
| Epic Integration Hub | APP-INTEGRATION-12 |
| Capability Registry reference | PORTFOLIO-SUMMARY — Confluence 900001 version 3 |
| Frontend Capability Index | Portfolio — Capability Index |

## Summary

Dashboard now shows portfolio total value and daily change with explicit
loading, empty and error states.

## Delivered scope

- Portfolio summary API.
- Dashboard summary card for desktop and mobile.

## Decisions

| Decision | Reason | Trade-off | Record |
| --- | --- | --- | --- |
| Reuse existing pricing precision | Preserve contract consistency | No new display precision | BB-120 |
| Accept Safari as unverified | Environment unavailable in initial release | Follow-up browser check required | BF-87 |

## Validation evidence

- Backend: 20 focused tests passed plus three smoke cases.
- Frontend: 8 tests and production build passed; responsive/manual checks passed.
- Safari visual check remains unverified and explicitly accepted.

## Known limitations and follow-ups

- Safari visual verification: linked follow-up Jira APP-121.
```

## 8. Jira completion

An cập nhật `APP-120`:

```markdown
## Delivery evidence

### Delivery Jira

- BB-120 — Portfolio summary API — In review
- BF-87 — Portfolio summary dashboard card — In review

### Completion documentation

- Confluence: APP-DOC-45
- Epic Integration Hub: APP-INTEGRATION-12 — Confluence content 900001 version 3
- Capability Registry: `PORTFOLIO-SUMMARY` — Confluence content 900001 version 3
- Frontend Capability Index: `Portfolio — Capability Index`
- Documentation status: Updated

### Final status

- Delivered outcome: users can see portfolio total and daily change.
- Known limitation: Safari visual check tracked in APP-121.
```

Jira chỉ chuyển `Done` sau khi các links trên đã được kiểm tra.

## 9. Traceability audit

| From | To | Evidence |
| --- | --- | --- |
| `APP-120` | `BB-120`, `BF-87`, `APP-INTEGRATION-12` | Coordination links |
| `PORTFOLIO-SUMMARY` Registry row | Confluence `900001`, version `3` | Canonical content identity |
| `APP-INTEGRATION-12` | Confluence `900001`, `BB-120`, `BF-87` | Epic mapping and Registry reference |
| `BB-120` | Confluence `900001`, version `3`, `BF-87` | READY_FOR_FE handoff |
| `BF-87` | Confluence `900001`, version `3`, `Portfolio — Capability Index` | FE ACKNOWLEDGED record |
| Confluence `900001` | `BB-120`, `BF-87` | Self-contained public contract |
| `APP-DOC-45` | Jira items, Confluence `900001`, Integration Hub | Completion document links |

Manager có thể bắt đầu từ bất kỳ record nào trong bảng và trace tới toàn bộ
delivery chain mà không phải tìm kiếm theo tên người hoặc nội dung chat.
