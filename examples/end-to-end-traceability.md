# Ví dụ traceability end-to-end

Ví dụ này dùng record giả định để minh họa một outcome được tách thành Jira
items trong hai projects `BB`/`BF`, triển khai bằng hai repositories/PRs, handoff
qua một Epic Integration Hub và hoàn tất bằng một Confluence document.

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

- GitHub Issues: Pending
- Merged PRs: Pending
- Completion document: Pending
```

Jira không chỉ định endpoint, component, file hoặc library.

`APP-120` là coordination item do Product Manager An sở hữu; executable
assignments trong ví dụ là GitHub Issues `#121` và `#122`. Vì vậy assignee gate
không reassign `APP-120`. Nếu team tạo Jira Story/Task/Bug/Feature riêng để Nam
hoặc Linh yêu cầu AI thực thi, Jira item đó phải assign đúng developer trước khi
implementation bắt đầu.

## 2. Issue decomposition

| Jira / GitHub Issue | Outcome | Labels | Primary owner | Dependency |
| --- | --- | --- | --- | --- |
| `BB-120` / `#121` | Cung cấp portfolio summary API | `type:feature`, `area:backend`, `priority:p1` | Nam | Existing holdings/pricing contracts |
| `BF-87` / `#122` | Hiển thị portfolio summary trên dashboard | `type:feature`, `area:frontend`, `priority:p1` | Linh | Contract handoff từ `BB-120` / `#121` |

Manager cập nhật coordination item `APP-120`, cross-links `BB-120` và `BF-87`,
và link cả hai tới cùng một Integration Hub.

### Backend Capability Registry

```markdown
| Capability ID | Scope / domain / transport | Repository artifact | Canonical Confluence content | Owner / version |
| --- | --- | --- | --- | --- |
| `PORTFOLIO-SUMMARY` | Derivatives / User / API | `contracts/openapi.yaml` | `BE-DOC-PORTFOLIO-SUMMARY` | Backend / Pending |
```

Registry row là canonical mapping. Page `BE-DOC-PORTFOLIO-SUMMARY` thuộc Folder
`Derivatives — User — API`; Hub và FE Index chỉ tham chiếu row này.

### Epic Integration Hub `APP-INTEGRATION-12`

```markdown
# Portfolio summary — Integration Hub

- Backend Epic/Task: BB-120
- Frontend Epic/Task: BF-87
- Coordinator: An

| Registry reference | BE issue/PR | Handoff state | FE issue/PR | Breaking |
| --- | --- | --- | --- | --- | --- |
| `PORTFOLIO-SUMMARY` — `BE-CAP-REGISTRY#PORTFOLIO-SUMMARY` | #121 / Pending | DRAFT | #122 / Pending | None |
```

Hub là Epic current-state index. OpenAPI body vẫn thuộc Backend repository; Hub
chỉ tham chiếu Registry row và không copy schema.

## 3. Backend Issue `#121`

```markdown
# [Feature] Cung cấp portfolio summary API

## Traceability

- Jira task: BB-120; coordination item APP-120
- Product docs: Confluence/APP-PORTFOLIO-OVERVIEW
- Epic Integration Hub: APP-INTEGRATION-12
- Capability ID: PORTFOLIO-SUMMARY
- Capability Registry reference: BE-CAP-REGISTRY#PORTFOLIO-SUMMARY
- Related issues: BF-87 / #122 consumes this API

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
- Frontend Jira/GitHub issue: BF-87 / #122
- Capability ID / Registry reference:
  `PORTFOLIO-SUMMARY` / `BE-CAP-REGISTRY#PORTFOLIO-SUMMARY`
- Canonical contract artifact/version: `contracts/openapi.yaml`, pending merge
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

Sau merge, Nam cập nhật Hub và linked FE issue:

```markdown
## BE → FE handoff

- Backend Jira/GitHub issue and merged PR: BB-120 / #121 / #131
- Frontend Jira/GitHub issue: BF-87 / #122
- Capability ID / Registry reference:
  `PORTFOLIO-SUMMARY` / `BE-CAP-REGISTRY#PORTFOLIO-SUMMARY`
- Canonical document content ID: `BE-DOC-PORTFOLIO-SUMMARY`
- Canonical contract artifact/version/commit:
  `contracts/openapi.yaml`, `portfolio-summary-v1`, merge commit `aaaa1111`
- Authentication: existing authenticated portfolio scope
- Error cases: `401` unauthenticated; empty portfolio returns `200` with zeros
- Test environment: local test API; three sanitized smoke cases passed
- Breaking/migration impact: None
- Known limitations/unverified items: None
- State: READY_FOR_FE
- Ready by: Nam at 2026-07-17T14:20:00+07:00
```

Nam comment cùng block vào `BF-87`/`#122`. Linh đọc exact artifact/version và
ghi `ACKNOWLEDGED — portfolio-summary-v1 — 2026-07-17T14:30:00+07:00`. FE không
tự tổng hợp contract từ nội dung `#121` và PR comments.

## 5. Frontend Issue `#122`

```markdown
# [Feature] Hiển thị portfolio summary trên dashboard

## Traceability

- Jira task: BF-87; coordination item APP-120
- Design: Figma/portfolio-dashboard-v2
- Epic Integration Hub: APP-INTEGRATION-12
- Capability ID: PORTFOLIO-SUMMARY
- Capability Registry reference: BE-CAP-REGISTRY#PORTFOLIO-SUMMARY
- Frontend Capability Index: `Portfolio — Capability Index`
- Dependency: `portfolio-summary-v1` handoff from BB-120 / #121 — ACKNOWLEDGED

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
- Use the contract delivered by #121.

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
Links: BF-87, APP-120, APP-INTEGRATION-12, Closes #122, consumes portfolio-summary-v1 from #131
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
| GitHub Issues | #121, #122 |
| Merged PRs | #131, #132 |
| Epic Integration Hub | APP-INTEGRATION-12 |
| Capability Registry reference | BE-CAP-REGISTRY#PORTFOLIO-SUMMARY |
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
| Reuse existing pricing precision | Preserve contract consistency | No new display precision | #121/#131 |
| Accept Safari as unverified | Environment unavailable in initial release | Follow-up browser check required | #122/#132 |

## Validation evidence

- Backend: 20 focused tests passed plus three smoke cases.
- Frontend: 8 tests and production build passed; responsive/manual checks passed.
- Safari visual check remains unverified and explicitly accepted.

## Known limitations and follow-ups

- Safari visual verification: linked follow-up issue #133.
```

## 8. Jira completion

An cập nhật `APP-120`:

```markdown
## Delivery evidence

### GitHub Issues

- #121 — Portfolio summary API — Closed
- #122 — Portfolio summary dashboard card — Closed

### Merged Pull Requests

- #131 — feat(portfolio): add summary endpoint — Merged
- #132 — feat(portfolio): show dashboard summary — Merged

### Completion documentation

- Confluence: APP-DOC-45
- Epic Integration Hub: APP-INTEGRATION-12 — current contract `portfolio-summary-v1`
- Capability Registry: `PORTFOLIO-SUMMARY` — `BE-CAP-REGISTRY#PORTFOLIO-SUMMARY`
- Frontend Capability Index: `Portfolio — Capability Index`
- Documentation status: Updated

### Final status

- Delivered outcome: users can see portfolio total and daily change.
- Known limitation: Safari visual check tracked in #133.
```

Jira chỉ chuyển `Done` sau khi các links trên đã được kiểm tra.

## 9. Traceability audit

| From | To | Evidence |
| --- | --- | --- |
| `APP-120` | `BB-120`, `BF-87`, `APP-INTEGRATION-12` | Coordination links |
| `PORTFOLIO-SUMMARY` Registry row | `contracts/openapi.yaml`, `BE-DOC-PORTFOLIO-SUMMARY` | Canonical artifact and content links |
| `APP-INTEGRATION-12` | `PORTFOLIO-SUMMARY` Registry row, `BB-120`, `BF-87` | Epic mapping and Registry reference |
| `BB-120` / `#121` | `PORTFOLIO-SUMMARY`, `portfolio-summary-v1`, `BF-87` / `#122` | READY_FOR_FE handoff |
| `BF-87` / `#122` | `PORTFOLIO-SUMMARY`, `portfolio-summary-v1`, `Portfolio — Capability Index` | FE ACKNOWLEDGED record |
| `#121` | `feature/121-portfolio-summary-api`, `#131` | Branch name và `Closes #121` |
| `#122` | `feature/122-portfolio-summary-card`, `#132` | Branch name và `Closes #122` |
| `#131`, `#132` | `APP-INTEGRATION-12`, `APP-DOC-45` | Hub and completion metadata |
| `APP-DOC-45` | Jira items, issues, PRs, Integration Hub | Completion document links |

Manager có thể bắt đầu từ bất kỳ record nào trong bảng và trace tới toàn bộ
delivery chain mà không phải tìm kiếm theo tên người hoặc nội dung chat.
