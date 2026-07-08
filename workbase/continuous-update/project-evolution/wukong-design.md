# wukong 设计说明书

> **项目**：本地 Agent 记忆系统，用于 opencode、Claude Code 等多 agent 工具间的信息共享与通信
> **仓库**：https://github.com/yyl-support/wukong
> **本地路径**：`D:\user\code\wukong`
> **日期**：2026-06-08

---

## 1. 目标

构建一套跨 agent 工具的本地记忆系统，降低多个 agent 窗口间的信息传递成本，覆盖三个层次：

- **会话级**（短期）：每个 agent 会话的上下文、决策、未完成任务
- **项目级**（长期）：项目架构知识、代码关键位置、踩坑经验、约定规范
- **实时级**（通信）：多 agent 窗口同时工作时交换状态、任务分配、中间结果

并提供 Web UI 可视化界面，支持主流操作系统（Windows / macOS / Linux）。

---

## 2. 技术选型

### TypeScript 层 — 主进程（记忆系统 + MCP + Web UI）

| 层 | 选择 | 理由 |
|---|---|---|
| 运行时 | Node.js 18+ | 跨平台一致，MCP SDK 原生支持 |
| 语言 | TypeScript (strict) | 类型安全，可维护 |
| MCP SDK | @modelcontextprotocol/sdk | 官方，stdio transport |
| HTTP 框架 | Hono (Node adapter) | 轻量，原生 TS，内置 serve-static |
| 数据库 | better-sqlite3 | 同步 API，预编译二进制跨平台，零配置 |
| 全文搜索 | SQLite FTS5 | 内置 |
| Web UI | HTML + HTMx + Pico.css + SSE | 无构建步骤，服务端渲染局部刷新 |
| 构建 | tsup → 单文件 | shebang 可执行 |
| 包管理 | pnpm | lockfile 跨平台一致 |
| 测试 | vitest | 快，原生 TS |
| 代码规范 | biome | 统一替代 eslint + prettier |
| 日志 | pino | 低开销，结构化 JSON 日志，跨平台 |

### Python 层 — AI 增强插件（可选，MVP 不实现）

> MVP 阶段不实现。当知识库规模增大（>100 条）后，以插件形式接入，提供语义搜索、AI 摘要、智能推荐能力。

| 层 | 选择 | 理由 |
|---|---|---|
| 运行时 | Python 3.11+ | 跨平台 |
| Web 框架 | FastAPI | 高性能，自动文档 |
| 嵌入模型 | sentence-transformers (all-MiniLM-L6-v2) | 本地，~80MB，无需 GPU |
| 向量存储 | chromadb | 嵌入式 |
| 进程通信 | localhost HTTP + shared token | 仅本机回环 |

---

## 3. 架构总览

```
wukong daemon
│
├── MCP Server (TS/Hono)
│     └──◄── stdio ──►  opencode / claude code
│     │
│     ▼
├── HTTP Server (Hono)
│     └──◄── SSE :51820 ──  浏览器 Web UI
│     │
│     ▼
├── SQLite DB (memory.db)
│     └──◄── better-sqlite3  (知识索引 + 会话 + 消息)
│
├── 项目目录: knowledge/ skill/ log/ scripts/
│     └── (物理文件存储)
│
└── [未来插件] ← Python 语义搜索 / AI 摘要
```

### 职责划分

| 层 | 职责 |
|---|---|
| TS 主进程 | MCP 协议、SQLite CRUD、HTTP 路由、Web UI 渲染、日志管理 |
| SQLite | 知识文件索引、会话、消息的持久化存储；**不存储知识内容本身** |
| Python 插件（未来） | 语义搜索（embedding）、AI 摘要生成、智能推荐 |

---

## 4. 知识管理系统

### 4.1 存储策略

知识以**物理文件**形式存储，SQLite 仅保存**索引元数据**。

**双端存储**：
- **本地**：`{projectRoot}/knowledge/` 目录
- **远端**：GitHub 仓库 `{projectRoot}/knowledge/` 目录（通过 git push 同步）

**目录规则**（项目根目录下）：

```
{projectRoot}/
└── knowledge/
    ├── doc/        ← Word、PDF 等文档格式
    ├── picture/    ← 图片格式 (png, jpg, svg, etc.)
    ├── md/         ← Markdown 格式
    └── other/      ← 其他格式
```

**文件命名规则**：`yyyy-mm-dd-任务描述-作用.扩展名`

示例：
```
2026-06-08-api-redesign-架构评审意见.md
2026-06-07-bugfix-502-根因分析图.png
2026-06-05-deploy-flow-发布流程图.png
2026-06-01-backlog-issue29-需求分析说明书.md
```

### 4.2 知识索引表 (knowledge_index)

```sql
CREATE TABLE knowledge_index (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  project         TEXT NOT NULL,              -- 所属项目
  path            TEXT NOT NULL UNIQUE,       -- 相对路径: knowledge/md/2026-06-08-xxx.md
  name            TEXT NOT NULL,              -- 文件名（含扩展名）
  format          TEXT NOT NULL,              -- doc / picture / md / other
  saved_at        TEXT NOT NULL,              -- 保存日期 (yyyy-mm-dd)，从文件名解析
  task            TEXT,                       -- 所属任务，从文件名解析
  purpose         TEXT,                       -- 作用描述，从文件名解析
  description     TEXT,                       -- 人工/AI 生成的简短描述
  summary         TEXT,                       -- AI 摘要，用于 FTS 全文检索（未来由 Python 插件填充）
  tags            TEXT,                       -- JSON: ["tag1", "tag2"]
  enable          INTEGER DEFAULT 1,          -- 是否有效: 1=有效, 0=废弃
  remote          INTEGER DEFAULT 0,          -- 是否已同步到远端 GitHub: 1=已同步, 0=未同步
  source_session  TEXT,                       -- 来源会话 ID
  file_size       INTEGER,                    -- 文件大小 (bytes)
  checksum        TEXT,                       -- SHA256 校验和，用于完整性/变更检测
  created_at      TEXT DEFAULT (datetime('now')),
  updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_ki_project ON knowledge_index(project);
CREATE INDEX idx_ki_format ON knowledge_index(project, format);
CREATE INDEX idx_ki_enable ON knowledge_index(project, enable);
CREATE INDEX idx_ki_remote ON knowledge_index(project, remote);
CREATE INDEX idx_ki_saved_at ON knowledge_index(project, saved_at);
CREATE VIRTUAL TABLE knowledge_fts USING fts5(
  name, task, purpose, description, tags,
  content=knowledge_index
);
```

**列设计说明**：

| 列 | 作用 |
|---|---|
| `path` | 定位物理文件 |
| `name` | 快速文件名匹配 |
| `format` | 按格式分类检索 |
| `saved_at` / `task` / `purpose` | 从文件名自动解析的结构化字段 |
| `description` | 人工可编辑的简短说明 |
| `summary` | AI 自动生成的内容摘要（插件功能，MVP 阶段为 NULL） |
| `tags` | 灵活的标签体系，支持交叉分类 |
| `enable` | 软删除/废弃标记，保留历史记录 |
| `remote` | 同步状态追踪 |
| `source_session` | 溯源：哪次会话产生的这条知识 |
| `file_size` | 存储空间管理 |
| `checksum` | 完整性校验 + 变更检测（文件修改后自动更新） |

### 4.3 知识保存流程

```
Agent 调用 knowledge_save
    │
    ├── 1. 解析文件名 → 提取 saved_at, task, purpose
    ├── 2. 确定子目录 → knowledge/{format}/
    ├── 3. 写入物理文件 → {projectRoot}/knowledge/{format}/{name}
    ├── 4. 计算 SHA256 → 写入 checksum
    ├── 5. INSERT 索引记录 → knowledge_index
    ├── 6. 日志记录 → [INFO] knowledge_saved: {path} ({file_size} bytes)
    └── 7. 返回 { id, path }
```

### 4.4 知识同步到远端

```
wk sync
    │
    ├── 扫描 knowledge_index WHERE remote = 0 AND enable = 1
    ├── 复制文件到 workspace/knowledge/
    ├── git add / git commit / git push
    └── UPDATE knowledge_index SET remote = 1
```

---

## 5. 数据模型（其他表）

### 5.1 会话表 (sessions)

```sql
CREATE TABLE sessions (
  id            TEXT PRIMARY KEY,           -- UUID
  project       TEXT NOT NULL,              -- 项目名
  agent         TEXT NOT NULL,              -- opencode / claude-code / wk-1 / wk-2
  status        TEXT DEFAULT 'active',      -- active / completed
  summary       TEXT,                       -- 内容摘要
  decisions     TEXT,                       -- JSON: [{decision, reason, time}]
  pending_tasks TEXT,                       -- JSON: [{task, status}]
  created_at    TEXT DEFAULT (datetime('now')),
  updated_at    TEXT DEFAULT (datetime('now'))
);
```

### 5.2 消息表 (messages)

```sql
CREATE TABLE messages (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  project     TEXT NOT NULL,
  from_agent  TEXT NOT NULL,
  to_agent    TEXT,                        -- NULL = 广播
  type        TEXT DEFAULT 'info',         -- info / task / question / result / handoff
  content     TEXT NOT NULL,
  is_read     INTEGER DEFAULT 0,
  created_at  TEXT DEFAULT (datetime('now'))
);
CREATE INDEX idx_messages_unread ON messages(project, to_agent, is_read);
```

---

## 6. MCP 接口

### 6.1 Tools

| Tool | 模块 | 参数 | 返回值 |
|---|---|---|---|
| `session_start` | Session | `{project, agent}` | `{sessionId}` |
| `session_summary` | Session | `{sessionId}` | `{summary, decisions, pendingTasks}` |
| `session_handoff` | Session | `{sessionId}` | `{handoffDoc}` |
| `knowledge_search` | Knowledge | `{project, query, format?, tags?}` | `[{id, name, path, format, description, score}]` |
| `knowledge_save` | Knowledge | `{project, name, format, content?, filePath?}` | `{id, path}` |
| `knowledge_get` | Knowledge | `{id}` | `{name, path, format, description, summary, tags, ...}` |
| `knowledge_list` | Knowledge | `{project, format?, enable?, remote?, tags?}` | `[{id, name, path, format, saved_at, ...}]` |
| `knowledge_update` | Knowledge | `{id, description?, tags?, enable?}` | `{ok}` |
| `knowledge_delete` | Knowledge | `{id}` | `{ok}` (软删除：enable=0) |
| `knowledge_sync_status` | Knowledge | `{project}` | `{total, synced, pending}` |
| `message_send` | Message | `{project, toAgent?, type, content}` | `{id}` |
| `message_poll` | Message | `{project, agent}` | `[{id, fromAgent, type, content, time}]` |
| `message_mark_read` | Message | `{ids[]}` | `{ok}` |

### 6.2 Resources

| Resource URI | 内容 |
|---|---|
| `memory://session/current` | 当前活跃会话的完整上下文 |
| `memory://knowledge/{project}` | 项目知识库统计（总数/各格式数/同步状态） |
| `memory://handoff/latest` | 最近一次交接文档 |

---

## 7. 进程架构

### 7.1 生命周期

```
wk start
    │
    ├── 检查 Node.js 环境
    ├── 读取 ~/.wk/config.json
    ├── 确保项目目录结构存在 (knowledge/{doc,picture,md,other}, skill, log, scripts)
    ├── 初始化日志系统 (pino → log/ 目录)
    ├── [INFO] Starting wukong daemon...
    ├── 启动 TS 主进程 (localhost:51820)
    ├── 写入 ~/.wk/daemon.pid
    ├── [INFO] Daemon ready. Web UI: http://localhost:51820
    └── 前台运行，Ctrl+C 或 wk stop 终止
```

### 7.2 MCP Tool 请求流

```
Agent → MCP tool call → TS 主进程
    │
    ├── 基础操作 → 直接 SQLite 读写
    └── 文件操作 → 读写 knowledge/ 物理文件
```

### 7.3 跨 Agent 消息流

```
Agent A → message_send → INSERT messages → Agent B → message_poll → SELECT unread
```

### 7.4 数据库策略

- 项目级数据库：`{projectRoot}/.agent-memory/memory.db`
- 全局数据库：`~/.wk/global.db`
- WAL 模式开启，`busy_timeout=5000`
- 首次访问自动建库 + migration
- SQLite 文件仅在当前用户下可读写

---

## 8. 日志系统

### 8.1 技术选型

使用 **pino**（Node.js 端）。未来 Python 插件接入后，Python 端使用 Python logging。

### 8.2 日志等级

| 等级 | 用途 |
|---|---|
| `trace` | 数据库每条 SQL、文件 I/O 细节 |
| `debug` | MCP tool 参数与返回值 |
| `info` | 会话开始/结束、知识保存/删除、消息收发、服务启动/停止 |
| `warn` | 同步失败、文件校验异常、配置缺失 |
| `error` | 未捕获异常、数据库损坏、文件写入失败 |

### 8.3 日志输出

- **控制台**：`info` 及以上（开发时 `debug`）
- **文件**：`log/daemon.log`（全量，按天切割，保留 30 天）
- **格式**：JSON 结构（pino 默认），每行一条

### 8.4 关键日志节点

```
[INFO]  Daemon starting (pid=12345, port=51820)
[INFO]  Database initialized: /path/to/project/.agent-memory/memory.db
[INFO]  Session started: {sessionId, project, agent}
[INFO]  Session completed: {sessionId, taskCount, decisionCount}
[INFO]  Knowledge saved: {path, format, fileSize}
[WARN]  Knowledge checksum mismatch, file may be modified: {path}
[INFO]  Knowledge synced to remote: {count} files
[INFO]  Message sent: {from, to, type}
[ERROR] Failed to write knowledge file: {path} - {error.message}
[INFO]  Daemon stopping...
```

### 8.5 日志文件结构

```
log/
├── daemon.log           ← 当前日志
├── daemon.2026-06-07.log ← 历史日志（自动切割）
└── daemon.2026-06-06.log
```

---

## 9. Web UI 设计

### 9.1 布局

```
顶栏: wukong  ◉ connected   项目: backlog   ⚙ 设置
│
├── 会话列表 (左 1/4)
│     ├── 新建会话
│     ├──● #a1f2 活跃 → opencode → 3 任务待办
│     └──○ #b3d8 完成 → claude → 已产出交接
│
├── 知识库 (中 2/4)
│     ├── 搜索:[      ]  📋全部 ⚙过滤
│     ├── 2026-06-08 → api-redesign → 架构评审意见 → ☁ 已同步 ✅
│     └── 2026-06-07 → bugfix-502 → 根因分析图.png → ☁ 待同步 🖼
│
└── 消息总线 (右 1/4)
      ├── 发送给:[opencode▼]
      ├── 🤖 opencode 12:03 → "task done..."
      ├── 🤖 claude 12:01 → "开始 code review"
      └── 📝 输入消息... → [发送]
▼
状态栏: wk v0.1.0 | 知识 23条(3待同步) | 消息 5
```

### 9.2 知识库面板功能

- 搜索栏：关键词（FTS5 全文搜索）
- 过滤器：按格式（doc/picture/md/other）、按同步状态、按标签
- 知识卡片展示：文件名、日期、描述、同步状态图标、格式图标
- 点击卡片：预览内容（md 渲染、图片预览、其他格式显示元数据）
- 右键菜单：打开文件 / 编辑描述 / 标记废弃 / 同步到远端

### 9.3 实现方案

- 无前端框架，纯 HTML + HTMx + Pico.css
- 服务端渲染 HTML 片段，HTMx 处理动态局部刷新
- SSE (`/ui/events`) 推送新消息和状态变更
- 三个面板独立路由：`/ui/sessions`、`/ui/knowledge`、`/ui/messages`

### 9.4 前端文件结构

```
/templates/
  layout.html
  panels/
    sessions.html
    sessions-detail.html
    knowledge.html
    knowledge-detail.html
    messages.html
/public/
  app.css
  app.js
```

---

## 10. CLI & 配置

### 10.1 命令

| 命令 | 功能 |
|---|---|
| `wk start` | 启动 daemon（前台运行） |
| `wk start -d` | 后台运行（daemonize） |
| `wk stop` | 停止 daemon |
| `wk ui` | 打开浏览器 → localhost:51820 |
| `wk status` | 显示运行状态、知识统计、日志路径 |
| `wk sync` | 同步未推送知识到远端 GitHub |
| `wk config` | 打印当前配置 |
| `wk init` | 初始化项目：创建 knowledge/ skill/ log/ scripts/ 目录，注入 MCP 配置片段 |
| `wk mcp` | 以 MCP stdio transport 启动（供 agent 调用） |

### 10.2 配置文件

路径：`~/.wk/config.json`

```json
{
  "port": 51820,
  "python": {
    "enabled": false
  },
  "database": {
    "globalPath": "~/.wk/global.db"
  },
  "ui": {
    "theme": "auto"
  },
  "log": {
    "level": "info",
    "dir": "./log",
    "retentionDays": 30
  },
  "git": {
    "remote": "origin",
    "branch": "main",
    "autoSync": false
  }
}
```

### 10.3 Agent 侧 MCP 配置

```json
{
  "mcpServers": {
    "wk": {
      "command": "npx",
      "args": ["wk", "mcp"]
    }
  }
}
```

### 10.4 Subagent 命名规范

以 wukong 工程启动 agent 时，所有 subagent 自动按 `wk-{编号}` 格式命名。

- 编号从 1 开始递增，由 daemon 维护全局计数器
- 会话表 `agent` 字段记录 subagent 名（如 `wk-1`, `wk-2`）
- 消息总线 `from_agent` / `to_agent` 使用此命名标识
- Web UI 会话列表和消息面板展示对应名称
- 计数器存储在全局数据库 `agent_seq` 表中，跨会话递增

```sql
CREATE TABLE agent_seq (
  project   TEXT NOT NULL PRIMARY KEY,
  last_seq  INTEGER DEFAULT 0
);
```

**命名示例**：

```
wukong daemon 启动
  → 用户通过 opencode 连接 → agent 名为 "opencode"（主 agent 保持原名）
  → opencode 调用 subagent-driven-development → spawn wk-1
  → claude code 连接 → agent 名为 "claude-code"
  → claude code 调用 dispatching-parallel-agents → spawn wk-2, wk-3
```

**规则**：
- 用户手动启动的 agent 进程保持原名（opencode / claude-code）
- 通过 wukong 管理的 skill 派生的 subagent 使用 `wk-{n}` 命名
- 编号全局唯一，不回收

### 10.5 CLAUDE.md / AGENTS.md 注入

`wk init` 在目标项目根目录执行时：

1. 创建 `knowledge/{doc,picture,md,other}/`、`skill/`、`log/`、`scripts/` 目录
2. 若存在 `AGENTS.md` → 追加 MCP 配置和使用说明
3. 若存在 `CLAUDE.md` → 同上
4. 若都不存在 → 创建 `AGENTS.md`，包含 MCP 配置 + wukong 工具使用规范

CLAUDE.md 作用域说明：仅在 wukong 项目目录下启动的 agent 才能自动加载该文件。对其他项目，需通过 `wk init` 注入配置。

---

## 11. Python 增强插件（未来）

> MVP 阶段不实现。当知识库规模增大后以插件形式接入。

| 端点 | 方法 | 功能 |
|---|---|---|
| `/health` | GET | 健康检查 |
| `/semantic-search` | POST | `{query, project, top_k}` → 语义搜索 knowledge_index |
| `/generate-summary` | POST | `{sessionId, messages[]}` → 会话摘要 |
| `/generate-knowledge-summary` | POST | `{filePath, format}` → 读取文件内容并生成摘要 |
| `/recommend` | POST | `{project, context, top_k}` → 相关知识推荐 |

---

## 12. 安全设计

- 所有服务绑定 `127.0.0.1`，不暴露局域网
- Web UI API 使用内嵌 token 鉴权
- SQLite 数据库文件权限仅当前用户可读写
- 不存储任何密钥、凭证等敏感信息

---

## 13. 目录结构

```
D:\user\code\wukong/
├── src/
│   ├── index.ts               # 包入口
│   ├── cli.ts                  # CLI 命令解析
│   ├── server.ts               # TS 主进程（Hono HTTP + MCP）
│   ├── mcp.ts                  # MCP Server 定义
│   ├── db/
│   │   ├── connection.ts       # SQLite 连接管理
│   │   ├── migrate.ts          # 建表 migration
│   │   └── query.ts            # 查询辅助
│   ├── modules/
│   │   ├── session/
│   │   │   ├── tools.ts
│   │   │   └── store.ts
│   │   ├── knowledge/
│   │   │   ├── tools.ts        # MCP tool: search/save/get/list/update/delete
│   │   │   ├── store.ts        # DB CRUD + 文件系统操作
│   │   │   ├── parser.ts       # 文件名解析 (→ saved_at, task, purpose)
│   │   │   └── sync.ts         # Git 同步逻辑
│   │   └── message/
│   │       ├── tools.ts
│   │       └── store.ts
│   ├── logger/
│   │   └── index.ts            # pino 日志配置与导出
│   ├── ui/
│   │   ├── routes.ts           # UI 路由
│   │   ├── templates/          # HTML 模板
│   │   │   ├── layout.html
│   │   │   └── panels/
│   │   └── public/             # 静态资源
│   │       ├── app.css
│   │       └── app.js
│   └── shared/
│       └── types.ts            # 共享类型
├── knowledge/                  # 知识物理文件存储
│   ├── doc/
│   ├── picture/
│   ├── md/
│   └── other/
├── skill/                      # Agent 使用的 skill 文件
├── log/                        # 日志输出目录
├── scripts/                    # 自动化脚本
├── tests/
├── CLAUDE.md                   # Claude Code 配置（本仓库内生效）
├── package.json
├── tsconfig.json
├── biome.json
└── README.md
```

---

## 14. 待定事项

- [ ] Python 插件何时接入（知识量阈值 > 100 条？）
- [ ] 后台运行（-d 模式）的跨平台实现方案
- [ ] 多项目间的知识迁移/引用机制
- [ ] FTS5 中文分词方案选型
