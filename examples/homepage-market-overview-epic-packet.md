# HomePage — Market Overview creation packet

Packet này là payload đã được duyệt cho Jira Epic `BB-5`, Confluence Epic
Integration Hub và initial child Feature của Epic. Epic creation là một bundle:
không hoàn thành nếu chưa tạo và read back ít nhất một child work item có thể
hiển thị trong backlog.

## Creation order and duplicate gate

1. Tìm các Epic active trong `BB` có summary hoặc scope liên quan `HomePage`,
   `Home`, `Dashboard` hoặc `Market Overview`.
2. Nếu có Epic tương tự, dừng và yêu cầu developer xác nhận reuse hoặc vẫn tạo
   mới; không tự tạo duplicate.
3. Trước external write đầu tiên, yêu cầu developer cung cấp ít nhất một initial
   child thuộc `Feature`, `Story`, `Task` hoặc `Bug`, gồm summary, scope tối
   thiểu, priority và assignee intent. Không tạo `Subtask` trực tiếp dưới Epic;
   Subtask chỉ được parent bởi một standard-level work item.
4. Resolve native Folder `BB-5 — HomePage — Market Overview` trong space
   `Berokaback`. Nếu thiếu Folder hoặc connector không tạo được Folder native,
   báo `FOLDER_CREATION_REQUIRED`; không tạo Hub ở space root/parent page.
5. Tạo Jira Epic `HomePage — Market Overview` trong project `BB`, link Hub và
   read back Epic trước khi tạo child.
6. Tạo initial child với `parent` bằng Epic key vừa read back và để Sprint unset,
   sau đó read back parent, Sprint, assignee, priority và Hub link.
7. Xác minh child bằng JQL và backlog UI trước khi báo `PASS`.

Nếu Epic đã tồn tại nhưng child creation thất bại, báo
`EPIC_CREATED_CHILD_FAILED` và tiếp tục từ Epic key đã tạo; không tạo Epic khác.

## Jira Epic payload

| Field | Value |
| --- | --- |
| Project | `BB` |
| Issue type | `Epic` |
| Summary | `HomePage — Market Overview` |
| Priority | `High` |
| Target period | Unset; giữ trong backlog |
| Assignee | Unassigned; child implementation items có owner riêng |
| Integration Hub | `HomePage — Integration Hub` |

```markdown
# HomePage — Market Overview

## Business goal

Cung cấp cho người dùng đã đăng nhập một điểm vào duy nhất để nắm nhanh diễn
biến thị trường và các mã họ quan tâm trước khi đi tới màn hình chuyên sâu.

## Success indicators

- Người dùng xem được snapshot các chỉ số thị trường chính.
- Người dùng xem được giá và biến động của các mã trong watchlist của họ.
- Người dùng xem được danh sách tin thị trường mới nhất.
- Loading, empty, unauthenticated và upstream-error states đều có hành vi rõ
  ràng, không hiển thị dữ liệu cũ như dữ liệu hiện hành.

## High-level scope

### In scope

- Authenticated HomePage market overview.
- Market index snapshot.
- Personal watchlist quote snapshot.
- Latest market-news list.
- Canonical BE contract và BE → FE versioned handoff.
- FE loading, empty và error presentation.

### Out of scope

- Portfolio, balance, P&L hoặc position summary.
- Order placement và trade execution.
- Market heatmap, sector analytics và top movers.
- Administration dashboard.

## Ownership and timeline

- Owner/coordinator: Unassigned at Epic creation; coordinator phải được đặt
  trước khi child items chuyển Ready.
- Priority: High
- Target period: Unset; backlog
- Stakeholders: Backend team, Frontend team

## Cross-team delivery

- Backend child items: tạo trong `BB`; sở hữu data/API contract, authentication,
  error semantics, freshness definition và sanitized test evidence.
- Frontend linked items: tạo trong `BF` dưới một BF Epic project-local. Hai Epic
  link bằng `Relates`; BB Feature `Blocks` một hoặc nhiều BF items có cùng
  immutable Capability IDs, Backend Capability Registry rows và Integration
  Hub references.
- Handoff gate: FE-dependent work chỉ Ready sau khi exact contract version đạt
  `READY_FOR_FE` và FE owner ghi `ACKNOWLEDGED`.

## Links

- Epic Integration Hub: https://beroka.atlassian.net/wiki/spaces/Berokaback/pages/68354049/HomePage+Integration+Hub
- Backend Capability Registry: Pending — central Governance registration required
- Backend initial Feature: [BB-7 — Market Index Chart](https://beroka.atlassian.net/browse/BB-7)
- Capability IDs: `MARKET-INDEX-SNAPSHOT`, `MARKET-INDEX-HISTORY`,
  `MARKET-INDEX-STREAM`
- Frontend Epic/items/Folder: Pending until approved FE work
- GitHub tracking: Pending — child issue owners update
- Completion document: Pending — coordinator updates after delivery
```

## Jira initial Feature payload

| Field | Value |
| --- | --- |
| Project | `BB` |
| Issue type | `Feature` |
| Summary | `Market Index Chart` |
| Created item | `BB-7` — `https://beroka.atlassian.net/browse/BB-7` |
| Parent | `BB-5` — HomePage — Market Overview |
| Priority | `High` |
| Sprint/target | Unset; backlog |
| Assignee | Unassigned |
| Capability IDs | `MARKET-INDEX-SNAPSHOT`, `MARKET-INDEX-HISTORY`, `MARKET-INDEX-STREAM` |
| Registry rows | Pending — exact Registry content ID required |
| Integration Hub | `https://beroka.atlassian.net/wiki/spaces/Berokaback/pages/68354049/HomePage+Integration+Hub` |

```markdown
# Market Index Chart

## Objective

Provide the authenticated HomePage with a market overview chart backed by a
versioned Backend contract.

## Expected outcomes

- The market-index snapshot exposes the latest overview state for each index.
- The chart-history snapshot exposes points with exactly `timestamp`,
  `closePrice` and `volume`.
- Realtime market-index updates are available through the authenticated
  `market-data` WebSocket.
- Authentication, empty, stale-data and upstream-error semantics are explicit.
- The versioned BE → FE handoff is linked from the HomePage Integration Hub.

## Scope

### In scope

- Market-index snapshot contract.
- Chart-history snapshot contract with `timestamp`, `closePrice` and `volume`.
- Realtime market-index contract over the `market-data` WebSocket.
- Sanitized validation evidence and the versioned BE → FE handoff.

### Out of scope

- Frontend implementation.
- `open`, `high` and `low` fields in the current chart-history snapshot.
- Market heatmap, top movers, sector analytics and trading actions.

## Links

- Parent Epic: https://beroka.atlassian.net/browse/BB-5
- Capability IDs: `MARKET-INDEX-SNAPSHOT`, `MARKET-INDEX-HISTORY`,
  `MARKET-INDEX-STREAM`
- Registry rows: Pending — exact Registry content ID required
- Integration Hub: https://beroka.atlassian.net/wiki/spaces/Berokaback/pages/68354049/HomePage+Integration+Hub
```

## Confluence Integration Hub payload

| Field | Value |
| --- | --- |
| Space | `Berokaback` |
| Required native Folder | `BB-5 — HomePage — Market Overview` |
| Current Folder status | Missing — developer must create and return URL/ID |
| Required parent location | Beroka-backend root |
| Title | `HomePage — Integration Hub` |
| Hub migration state | `FOLDER_CREATION_REQUIRED` |
| Backend Capability Registry | Pending — `ROUTING_REQUIRED` before capability-dependent write |
| Capability IDs | `MARKET-INDEX-SNAPSHOT`, `MARKET-INDEX-HISTORY`, `MARKET-INDEX-STREAM` |
| Backend Feature | `BB-7` |
| Frontend Epic/items/Folder | Pending until approved FE work |

Page `68354049` hiện đã tồn tại nhưng chưa được move trong packet này. Không tạo
Hub duplicate hoặc di chuyển page cho tới khi developer trả native Folder
URL/ID và connector có thể xác minh `parentId`, `parentType = Folder`.

```markdown
# HomePage — Integration Hub

## Ownership and links

- Owning space/native Epic Folder: Berokaback / `BB-5 — HomePage — Market Overview`
- Folder status: FOLDER_CREATION_REQUIRED
- Backend Capability Registry: Pending — exact content ID required
- Coordinator: Unassigned; required before child items become Ready
- Backend Epic: [BB-5 — HomePage — Market Overview](https://beroka.atlassian.net/browse/BB-5)
- Frontend Epic/Folder: Pending until approved FE work
- Frontend Capability Index: `HomePage — Capability Index` — Pending
- Backend repository issues/PRs: Pending — BE child owner updates
- Frontend repository issues/PRs: Pending — FE child owner updates

## Epic mapping

| Relationship | Source | Target | Jira link/readback |
| --- | --- | --- | --- |
| Paired Epics | BB-5 | Pending — BF Epic owner required after approved FE work | MAPPING_INCOMPLETE |

## Capability Registry references

| Registry row | BE Jira item | BF Jira item(s) | Handoff state | Owners | Breaking |
| --- | --- | --- | --- | --- | --- |
| `MARKET-INDEX-SNAPSHOT` — Registry Pending | [BB-7 — Market Index Chart](https://beroka.atlassian.net/browse/BB-7) | Pending until approved FE work | DRAFT | BE: Pending / BF: Pending | No |
| `MARKET-INDEX-HISTORY` — Registry Pending | [BB-7 — Market Index Chart](https://beroka.atlassian.net/browse/BB-7) | Pending until approved FE work | DRAFT | BE: Pending / BF: Pending | No |
| `MARKET-INDEX-STREAM` — Registry Pending | [BB-7 — Market Index Chart](https://beroka.atlassian.net/browse/BB-7) | Pending until approved FE work | DRAFT | BE: Pending / BF: Pending | No |

## Shared decisions

- Đây là Integration Hub duy nhất cho HomePage market overview.
- Backend Capability Registry sở hữu canonical Capability IDs và link exact
  artifact/version/content ID; Hub chỉ tham chiếu Registry rows.
- FE không tổng hợp contract từ nhiều issue descriptions hoặc chat messages.
- Title similarity không được dùng để suy ra Registry hoặc BB/BF relation.
- Contract thay đổi sau acknowledgement phải publish version mới, mark handoff
  cũ `SUPERSEDED` và notify linked FE item.

## Error and state contract

- Unauthenticated response, empty watchlist, partial upstream unavailability và
  total upstream failure phải được định nghĩa trong canonical BE contract.
- FE phải có loading, empty và error states tương ứng; không biến lỗi thành dữ
  liệu hợp lệ.

## Validation gates

- BE contract checks và sanitized runtime smoke evidence pass cho từng
  capability trước `READY_FOR_FE`.
- Market-index snapshot, chart-history fields và `market-data` WebSocket update
  path đều có sanitized contract/runtime evidence trước `READY_FOR_FE`.
- FE xác minh contract version đã acknowledge và test happy/loading/empty/error
  paths trước khi linked FE item Done.
- Epic chỉ Done khi required BE và FE outcomes hoàn thành và completion document
  đã link lại Hub.

## Changelog

- 2026-07-21 — DRAFT — approved initial scope: indices, watchlist and market news.
- 2026-07-21 — Linked Backend Feature BB-7 for Market Index Chart contract.
```

## Creation readback gate

Không báo tạo thành công nếu chưa xác minh:

- Jira key, project `BB`, issue type `Epic`, summary và priority `High`;
- target period/Sprint đều unset;
- Jira Epic link đúng Confluence Hub và Hub link ngược lại Epic;
- không có Hub duplicate trong Confluence;
- exact Capability IDs, Registry rows, Hub references và Jira
  `Relates`/`Blocks` links read back đúng, hoặc báo `ROUTING_REQUIRED` khi
  Registry chưa được central Governance đăng ký;
- Hub/page read back đúng native Folder bằng `parentId` và
  `parentType = Folder`; nếu Folder thiếu, báo `FOLDER_CREATION_REQUIRED`;
- ít nhất một child `Feature`, `Story`, `Task` hoặc `Bug` read back đúng parent
  `BB-5`; direct `Subtask` dưới Epic không hợp lệ;
- initial child có Sprint unset và query
  `parent = BB-5 AND Sprint is EMPTY` trả về đúng issue;
- initial child xuất hiện trực tiếp trong backlog của board `BB/34`;
- record URLs mở được với requesting developer.

Kết quả chỉ dùng một trong các trạng thái:

- `PASS`: Epic, Hub và initial child đều read back đúng; child đã được xác nhận
  hiển thị trong backlog UI.
- `EPIC_CREATED_CHILD_FAILED`: Epic đã tạo nhưng initial child chưa tạo hoặc
  readback thất bại; retry bằng Epic key hiện có.
- `CREATED_BUT_NOT_VISIBLE`: record và JQL đúng nhưng chưa xác nhận được backlog
  UI; không tự suy luận UI visibility từ Jira readback.
- `FAILED_READBACK`: external write có thể đã xảy ra nhưng readback không chứng
  minh được state; không tạo duplicate.
- `FOLDER_CREATION_REQUIRED`: native Epic Folder chưa tồn tại hoặc connector
  không thể tạo; developer tạo Folder và trả URL/ID trước Confluence write/move.
- `DOC_HIERARCHY_FAILED`: page write/move xảy ra nhưng readback không chứng minh
  được page nằm trực tiếp trong native Epic Folder.
- `MAPPING_INCOMPLETE`: FE work chưa được duyệt/tạo và owner follow-up đã được
  ghi; không được nâng handoff lên `READY_FOR_FE`.

Nếu connector không cung cấp board/backlog API, phải yêu cầu manual UI
confirmation trước `PASS`; không tự sửa board settings.
