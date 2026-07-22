# Quy trình phối hợp Development Team và AI Agents

Bộ tài liệu này chuẩn hóa cách một team 7-8 developers phối hợp với nhiều AI
agents để nhận việc, triển khai, review và trace kết quả từ Jira tới
Confluence.

## Bắt đầu nhanh

- Manager/Coordinator: đọc [quy trình vận hành](workflow.md), sau đó dùng
  [template Jira và Confluence](templates/jira-confluence.md) và
  [template GitHub Issue](templates/github-issue.md).
- Developer: đọc [quy tắc quản trị](governance.md), nhận một GitHub Issue đạt
  Definition of Ready và dùng [template Pull Request](templates/pull-request.md).
- AI agent: nhận một assignment theo
  [AI Agent Assignment Template](templates/ai-agent-assignment.md).
- Thành viên mới: xem
  [ví dụ traceability end-to-end](examples/end-to-end-traceability.md).

AI agent tự chọn một trong hai mode:

- `planning-only`: xác nhận project và active Epic trước khi trả draft hoặc tạo
  Jira item;
- `execution`: xác minh requesting developer là Jira assignee trước khi sửa
  source, đồng thời giữ nguyên branch ownership/handoff rules.

Planning không tự cấp quyền tạo Jira item. Jira reassignment chỉ xảy ra sau
explicit developer confirmation và phải được đọc lại thành công trước khi AI
implementation bắt đầu.

Jira creation chỉ hoàn thành khi item được đọc lại đúng và match đúng
board/backlog. Item đã tạo nhưng bị board filter, status mapping hoặc backlog
configuration che khuất phải được báo `CREATED_BUT_NOT_VISIBLE`; agent không tạo
duplicate để làm cho check pass.

## Language policy

- Tài liệu developers/managers trực tiếp đọc hoặc copy để làm việc được viết
  bằng tiếng Việt, giữ nguyên các thuật ngữ kỹ thuật English trên công cụ.
- Prompt và handoff contract dành riêng cho AI agents được viết bằng English
  để dùng nhất quán giữa Codex, Claude, Cursor, Gemini, Kimi và công cụ tương
  đương.

## Source of truth

| Hệ thống | Trách nhiệm |
| --- | --- |
| Jira | Outcome high-level, business context, priority, assignee, timeline và trạng thái tổng thể |
| GitHub Issue | Technical scope, acceptance criteria, dependencies, validation và work ownership |
| Backend repository contract artifact | OpenAPI/JSON Schema/event schema hoặc contract version hiện hành để FE consume |
| Git branch/commit | Lịch sử thay đổi của một GitHub Issue |
| GitHub Pull Request | Review, validation evidence, approval authorization và merge history |
| Confluence | Epic Integration Hub, tài liệu hoàn thành, quyết định, hướng dẫn sử dụng và kiến thức cần duy trì |

Không sao chép toàn bộ nội dung giữa các hệ thống. Mỗi record liên kết tới
source of truth kế tiếp bằng URL ổn định.

## Traceability model

```text
Shared business outcome
├── BB Epic/Task ── BE GitHub Issue ── BE PR ── contract artifact
├── BF Epic/Task ── FE GitHub Issue ── FE PR
├── Epic Integration Hub ── current contract links + handoff states
└── Confluence completion document ── kết quả sau khi cả hai bên hoàn thành
```

Các quan hệ mặc định:

- Một Jira task có thể tạo nhiều GitHub Issues.
- Một GitHub Issue thuộc đúng một Jira task chính.
- Một GitHub Issue có một primary owner, một implementation branch và một PR.
- Nếu một issue cần nhiều PR độc lập, tách issue trước khi triển khai.
- BE và FE Jira items ở hai projects liên kết trực tiếp với nhau và cùng trỏ tới
  đúng một Epic Integration Hub; không duplicate hub sang hai Confluence spaces.
- FE consume contract artifact/version được BE publish; FE không tự ghép contract
  hiện hành từ nhiều issue descriptions hoặc chat messages.
- Jira chỉ chuyển `Done` sau khi các issue cần thiết hoàn thành và Confluence
  đã được liên kết, hoặc documentation được đánh dấu `N/A` có lý do.

## Quy tắc không được bỏ qua

- Issue phải có `type`, `area`, `priority` labels; PR copy các labels này.
- AI tự gắn labels khi mapping rõ ràng. Nếu confusing, AI hỏi human/manager
  thay vì đoán.
- Một branch chỉ có một primary writer tại một thời điểm.
- AI có thể review mọi loại thay đổi.
- AI không approve hoặc merge khi chưa có human confirmation cho PR cụ thể.
- Validation chưa đủ thì PR giữ trạng thái Draft; phần chưa kiểm chứng phải
  được ghi rõ.
- BE change có Frontend impact chỉ được coi là handoff-ready khi contract đã
  publish, Integration Hub đã cập nhật và linked FE issue đã được thông báo.
- Giai đoạn initial dùng manual review/validation, chưa yêu cầu CI hoặc bot.

## Tài liệu trong bộ này

| Tài liệu | Mục đích |
| --- | --- |
| [workflow.md](workflow.md) | Lifecycle Jira → GitHub → Confluence và checklists vận hành |
| [governance.md](governance.md) | Roles, ownership, Ready/Done gates, review và AI authority |
| [jira-confluence.md](templates/jira-confluence.md) | Copy-paste templates cho high-level planning và completion docs |
| [github-issue.md](templates/github-issue.md) | Feature, Bug và Technical Task templates |
| [pull-request.md](templates/pull-request.md) | PR description, validation và approval template |
| [ai-agent-assignment.md](templates/ai-agent-assignment.md) | Vendor-neutral assignment, blocker và handoff contracts |
| [end-to-end-traceability.md](examples/end-to-end-traceability.md) | Ví dụ một Jira task được chia thành FE/BE issues và PRs |

## Khi nào mới thêm automation

Chỉ thêm CI, bot, CODEOWNERS hoặc GitHub Issue Forms khi lỗi quy trình lặp lại
cho thấy checklist thủ công không còn đủ. Automation phải củng cố workflow này,
không tạo thêm một source of truth mới.
