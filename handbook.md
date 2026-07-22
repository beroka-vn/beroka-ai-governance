# Handbook cài đặt và rollout AI agent integrations

Tài liệu này là preflight và rollout guide cho Backend/Frontend workflow.
Developer cài integration một lần trên client đang dùng; agent kiểm tra lại
trước khi đọc hoặc ghi GitHub, Jira hay Confluence.

## Phạm vi team workflow

| Hệ thống | Target cần truy cập |
| --- | --- |
| GitHub Backend | [`hungnx77/Beroka_Backend`](https://github.com/hungnx77/Beroka_Backend) |
| GitHub Frontend | Exact repository theo task trong [`cuongngo1801-beroka`](https://github.com/cuongngo1801-beroka?tab=repositories) |
| Jira Backend | Project `BB`, board `34` |
| Jira Frontend | Project `BF`, board `35` |
| Confluence Backend | Space [`Beroka-backend`](https://beroka.atlassian.net/wiki/spaces/Berokaback/overview) |
| Confluence Frontend | Space [`Beroka-frontend`](https://beroka.atlassian.net/wiki/spaces/Berokafron) |

Read access tới cả `BB` và `BF` là bắt buộc cho counterpart discovery. Write
access chỉ dùng trong project/repository/space thuộc request đã xác nhận. Nếu
Frontend repository chưa resolve thành một exact URL, agent dừng external write
và hỏi developer; không tự chọn từ organization list.

## Quy tắc chung

- Dùng account cá nhân của developer và least privilege.
- Không đặt token trong repository, `.env` được commit, `AGENTS.md`,
  `CLAUDE.md`, Cursor rules, prompt, log hoặc tài liệu này.
- Ưu tiên OAuth/connector UI. Nếu GitHub client bắt buộc PAT, lưu token trong
  user-level secret/config, giới hạn quyền và rotate khi bị lộ.
- Không cấu hình đồng thời plugin và MCP trùng nhau cho cùng provider.
- Cài đặt không đồng nghĩa với authorization. Developer phải hoàn thành OAuth
  và chọn đúng GitHub/Atlassian account.
- Agent không tạo live issue/page chỉ để kiểm tra connector.

## Kích hoạt trong repository

Bundle runtime gồm `handbook.md`, `governance.md`, `workflow.md` và `templates/`.
Không rollout `README.md`, `examples/`, `plans/` hoặc `specs/` như agent rules.

Sau khi copy bundle vào `docs/team-dev-ai-workflow/` của repository đích, cài
entrypoint tương ứng:

| Client | Template nguồn | Vị trí trong repository đích |
| --- | --- | --- |
| Codex | `templates/agent-entrypoints/AGENTS.md` | Merge vào root `AGENTS.md` |
| Claude Code | `templates/agent-entrypoints/CLAUDE.md` | Root `CLAUDE.md` |
| Cursor | `templates/agent-entrypoints/team-dev-ai-workflow.mdc` | `.cursor/rules/team-dev-ai-workflow.mdc` |

Không overwrite repository rules đang có. Repository-specific safety,
architecture và validation rules được giữ nguyên; entrypoint này chỉ thêm Jira,
GitHub và Confluence workflow. Các files rollout phải được review và track bằng
PR trong repository đích. Folder untracked hiện tại chỉ là design workspace,
không phải distribution mechanism cho team.

## Quyền tối thiểu

| Provider | Read bắt buộc | Write chỉ khi request cần | Không yêu cầu mặc định |
| --- | --- | --- | --- |
| GitHub | Repositories, Issues, PRs, checks | Create/update Issue, comment, branch/PR trong owned scope | Repository admin, secret management, destructive actions |
| Jira | Browse `BB` và `BF`, board/backlog, users, links | Create/edit/assign/link/transition item trong confirmed project | Jira admin, sửa board filter/workflow/scheme |
| Confluence | Đọc hai team spaces và shared Integration Hub | Tạo/update Folder/page trong confirmed owning space | Space admin, delete/move hàng loạt |

Permission không được mở rộng chỉ để làm preflight pass. Nếu action thực tế cần
quyền cao hơn, agent báo exact target/action và chờ người có authority.

## Codex

### Cách khuyến nghị: OpenAI plugins

```bash
codex plugin add github@openai-curated
codex plugin add atlassian-rovo@openai-curated
codex plugin list
```

Sau khi cài, mở Plugins/Connectors trong Codex, authorize GitHub và Atlassian,
rồi mở session mới nếu tools chưa xuất hiện.

Nếu Codex distribution không có plugin marketplace, dùng official MCP thay
thế, không dùng song song:

```bash
codex mcp add github --url https://api.githubcopilot.com/mcp/ --bearer-token-env-var GITHUB_PAT_TOKEN
codex mcp add atlassian --url https://mcp.atlassian.com/v1/mcp/authv2
```

`GITHUB_PAT_TOKEN` phải tồn tại trong environment của Codex và không được ghi
vào repository. Hoàn thành Atlassian OAuth khi Codex yêu cầu, sau đó dùng `/mcp`
để xác nhận hai servers có tools.

## Claude Code

Atlassian dùng remote MCP và OAuth:

```bash
claude mcp add --transport http atlassian https://mcp.atlassian.com/v1/mcp/authv2
```

Mở Claude Code, chạy `/mcp` và hoàn thành Atlassian authentication.

GitHub hosted MCP hiện cần GitHub PAT. Export PAT trong shell rồi thêm ở scope
`local` mặc định; không dùng `--scope project` vì cách đó tạo shared
`.mcp.json`:

```bash
claude mcp add-json github "{\"type\":\"http\",\"url\":\"https://api.githubcopilot.com/mcp\",\"headers\":{\"Authorization\":\"Bearer ${GITHUB_PAT}\"}}"
claude mcp list
claude mcp get github
```

Nếu `GITHUB_PAT` rỗng hoặc Claude version không hỗ trợ `add-json`, dừng và làm
theo official GitHub MCP guide; không hardcode token vào project file.

## Cursor

### Atlassian

Trong Cursor Marketplace, cài **Atlassian plugin for Cursor with MCP**, chọn
**Add to Cursor** và hoàn thành OAuth bằng đúng Atlassian account.

### GitHub

Dùng GitHub hosted MCP tại `https://api.githubcopilot.com/mcp/` theo official
GitHub **Install in Cursor** flow. Nếu cấu hình thủ công, dùng user-level
`~/.cursor/mcp.json`, không dùng project-level `.cursor/mcp.json` vì GitHub PAT
không được chia sẻ qua repository. Giới hạn permission của file nếu có token:

```bash
chmod 600 ~/.cursor/mcp.json
```

Restart Cursor, rồi kiểm tra server có green status trong **Settings → Tools &
Integrations → MCP Tools**. Cursor Agent CLI có thể kiểm tra thêm:

```bash
cursor-agent mcp list
cursor-agent mcp list-tools github
cursor-agent mcp list-tools atlassian
```

## Preflight bắt buộc

Agent chạy read-only preflight trước workflow:

1. Xác định authenticated GitHub và Atlassian account.
2. Đọc metadata của Backend repository; nếu request thuộc FE, resolve và đọc
   exact Frontend repository.
3. Đọc project `BB`/board `34` và project `BF`/board `35` để counterpart
   discovery hoạt động hai chiều.
4. Đọc hai Confluence spaces và xác nhận agent mở được shared Integration Hub;
   chỉ kiểm tra Folder/page hierarchy của owning space liên quan.
5. Chỉ kiểm tra write permission khi request thực tế cần external write; không
   tạo test record.

Kết quả đạt yêu cầu:

```text
Integration preflight
- Client: Codex | Claude Code | Cursor
- GitHub identity/Backend read: PASS
- GitHub Frontend target/read: PASS | NOT_REQUIRED | TARGET_REQUIRED
- Jira identity/BB read: PASS
- Jira BF read: PASS
- Confluence Beroka-backend read: PASS
- Confluence Beroka-frontend read: PASS
- Shared Integration Hub access: PASS | NOT_REQUIRED | FAIL
- Required write scope: NOT_REQUIRED | PASS | FAIL
- Result: PASS | INTEGRATION_BLOCKED
```

Khi thất bại, agent dừng phần phụ thuộc và báo đúng nguyên nhân:

```text
Integration blocked
- Client:
- Provider: GitHub | Atlassian
- Failure: PLUGIN_MISSING | AUTH_REQUIRED | WRONG_ACCOUNT | PERMISSION_DENIED | CONNECTION_FAILED
- Required target/action:
- Setup section:
- Work that can continue safely:
```

Không diễn giải `AUTH_REQUIRED` hoặc `PERMISSION_DENIED` thành record không tồn
tại. Sau khi developer sửa kết nối, agent phải chạy lại preflight.

## Deployment checklist

- [ ] Runtime bundle đã được copy vào repository đích và track bằng reviewed PR.
- [ ] Codex/Claude Code/Cursor entrypoint đã được merge/copy đúng vị trí.
- [ ] Agent session mới xác nhận đã đọc `handbook.md`, `governance.md` và
      `workflow.md` trước external work.
- [ ] GitHub Backend và exact Frontend repository routing đã được xác nhận.
- [ ] Jira có Epic/Feature/Story/Task/Bug, backlog được enable và status map đúng
      trên `BB/34` và `BF/35`.
- [ ] Account có quyền browse/create/edit/assign/link theo scope; Jira link types
      `Relates` và `Blocks` khả dụng.
- [ ] Hai Confluence spaces có native Folder/page permissions và FE mở được
      shared Integration Hub trong owning BE Folder.
- [ ] Plugin/MCP dùng đúng account, không cấu hình duplicate và không chứa secret
      trong repository.
- [ ] Một pilot task thật đã pass các scenarios bên dưới trước team-wide rollout.

Khi shared rules thay đổi, cập nhật BE và FE bằng paired reviewed PRs. Chỉ thêm
automation đồng bộ nếu manual drift thực sự lặp lại.

## Rollout pilot

Dùng một task thật, nhỏ; không tạo fake issue/page chỉ để test. Pilot đạt khi:

1. planning-only trả draft và không external write;
2. BF Epic creation quét BB candidates, chờ confirmation và tạo kèm một initial
   `Feature/Story/Task/Bug` visible trong backlog;
3. pure-FE item trả `NO_BACKEND_DEPENDENCY` và không tạo BB link/record;
4. confirmed BE dependency chưa có counterpart trả `MAPPING_INCOMPLETE`, không
   đoán hoặc tự tạo BB item;
5. Jira assignee, parents, `Relates`/`Blocks`, Capability ID, Hub row và
   documentation hierarchy đều read back đúng khi applicable.

Ghi client, authenticated accounts, exact records, commands/checks và kết quả.
Chỉ mở rollout cho team sau khi blocker của pilot đã được xử lý.

## Troubleshooting nhanh

| Hiện tượng | Kiểm tra |
| --- | --- |
| Không thấy tools | Plugin/MCP status, restart client hoặc mở session mới |
| OAuth lặp lại | Đúng account, browser callback, workspace admin policy |
| Đọc được nhưng không ghi được | Repository/project/space permission của account |
| GitHub `401`/`403` | PAT hết hạn hoặc thiếu scope; không tăng scope nếu chưa cần |
| Jira có nhưng Confluence không có | Atlassian product access và space permission riêng |
| Kết quả thuộc nhầm team | Authenticated identity và target URL/project/space |

## Tài liệu chính thức

- [GitHub MCP Server](https://github.com/github/github-mcp-server)
- [GitHub MCP for Codex](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-codex.md)
- [GitHub MCP for Claude Code](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md)
- [GitHub MCP for Cursor](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-cursor.md)
- [Atlassian Rovo MCP getting started](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/getting-started-with-the-atlassian-remote-mcp-server/)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [Cursor MCP](https://docs.cursor.com/context/model-context-protocol)
