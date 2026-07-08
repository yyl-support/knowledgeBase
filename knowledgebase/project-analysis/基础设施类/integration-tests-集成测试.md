---
tags:
  - 基础设施
  - 测试
  - 集成测试
---

# 基础设施类 — integration-tests 集成测试

> 仓库：`opensourceways/integration-tests`（公开，Mirror of `agentic-develop-playground/integration-tests`）
> 分析时间：2026-06-21
> 语言：Python / Shell
> 地址：https://github.com/opensourceways/integration-tests

## 仓库定位

opensourceways 全平台的**跨服务端到端集成测试仓库**，覆盖 17 个微服务的 API、UI、OAuth 流程验证。在 ai-flow 五阶段生命周期中对应 **Phase B2（submit 门禁）** 和 **Phase C（发布后集成测试）** 阶段。

## 目录结构

```
integration-tests/
├── .github/workflows/
│   ├── ci.yml                          # 标准测试 CI（push/PR 触发）
│   └── refine-on-comment.yml           # AI 驱动的测试设计审查+自动修订
├── CLAUDE.md                           # AI Agent 编码规则
├── README.md
├── services/                           # 17 个服务的测试套件
│   ├── <service-name>/
│   │   ├── base_community/             # 跨社区共享测试
│   │   │   ├── run_all.sh              # Shell 运行器
│   │   │   └── test_cases.py           # pytest 测试文件
│   │   ├── <community>_community/      # 社区特定测试
│   │   ├── common.py                   # 共享工具（部分服务）
│   │   └── conftest.py                 # pytest fixtures（部分服务）
│   └── ...
└── test_skills_base/                   # AI 技能定义
    ├── test-case-generator/            # 测试用例生成 Agent
    └── test-case-execution-assistant/  # 测试执行 Agent
```

## 服务覆盖（17 个服务）

| # | 服务 | 描述 | 测试类型 |
|---|------|------|---------|
| 1 | `app-cla-server` | CLA 签署平台 | Playwright UI 测试 |
| 2 | `datastat-server` | 数据统计服务 | API 测试 |
| 3 | `discourse-server` | Discourse 论坛集成 | OAuth 流程 + API |
| 4 | `forum-reply-robot` | 论坛自动回帖机器人 | 模块可导入性冒烟 |
| 5 | `mailman` | 邮件列表管理 | API 测试 |
| 6 | `meeting-platform` | 会议平台抽象层 | TestStrategy 文档 |
| 7 | `meeting-server` | 会议调度 API（多社区） | 完整 CRUD API 测试 |
| 8 | `om-dataarts` | 开源实习数据看板 | TestStrategy 文档 |
| 9 | `oneid-server` | OneID 统一认证 | API 测试 |
| 10 | `quickissue-server` | 快速 Issue 创建 | API 测试 |
| 11 | `robot-universal-assign` | Issue 自动指派机器人 | 完整 API + Webhook 测试 |
| 12 | `robot-universal-associate` | PR-Issue 关联机器人 | API 测试 |
| 13 | `robot-universal-cla` | PR CLA 检查机器人 | API 测试 |
| 14 | `robot-universal-label` | 自动标签机器人 | API 测试 |
| 15 | `robot-universal-lifecycle` | Issue/PR 生命周期管理 | API 测试 |
| 16 | `robot-universal-review` | 代码审查分配机器人 | API 测试 |
| 17 | `robot-universal-welcome` | 新贡献者欢迎机器人 | API 测试 |

## 测试框架与模式

### 技术栈

- **pytest**：核心测试框架
- **Playwright**：UI 自动化测试（app-cla-server）
- **requests**：HTTP API 调用
- **python-dotenv**：环境变量管理

### 四种测试模式

| 模式 | 代表服务 | 方法 |
|------|---------|------|
| **A — API 集成测试** | robot-universal-*, meeting-server | 直接 HTTP 调用 + Webhook 等待 + JSON 断言 |
| **B — 可导入性冒烟** | forum-reply-robot | 验证模块可导入无语法错误 |
| **C — UI 自动化** | app-cla-server | Playwright + Element-plus 组件交互 |
| **D — OAuth 流程重放** | discourse-server | requests.Session 重放完整 OAuth2 + OneID 登录 |

### 命名规范

```python
# 函数名
def test_tc_api_assign_001_auto_assign_on_create():
# ID 格式
# TC-API-<MODULE>-<NNN>  （API 测试）
# TC-UI-<MODULE>-<NNN>   （UI 测试）
```

### Docstring 结构（8 字段）

```python
"""
TC-API-ASSIGN-001 [正常流] auto_assign
模块: assign
优先级: P0
严重级别: Critical
前提条件: ...
步骤: ...
预期结果: ...
"""
```

### 断言模式

```python
assert resp.status_code == 200
assert resp.json().get("number"), "未拿到 issue number"
assert _assignee_login(detail) == my_login, f"创建时已指派的 assignee 被 Robot 覆盖"
expect(page.locator('.loginButton')).to_contain_text("Login")  # Playwright
```

### 环境变量

| 变量 | 服务 | 用途 |
|------|------|------|
| `GITCODE_TEST_TOKEN` | robot-universal-* | GitCode PAT |
| `COMMUNITY` | meeting-server | 切换社区配置 |
| `TEST_ACCOUNT` / `TEST_PASSWORD` | app-cla-server, meeting-server | 登录凭证 |
| `DISCOURSE_TEST_ACCOUNT` | discourse-server | Discourse 登录 |
| `HTTP_VERBOSE` | robot-universal-* | 请求/响应日志开关 |

## 共享基础设施 — `common.py` + `conftest.py`

`robot-universal-*` 系列 7 个服务共享同一套测试基础设施：

### `common.py`（~300 行）

| 功能 | 说明 |
|------|------|
| HTTP 层 | `_send()` 封装 + 控制台日志 + JSONL 文件日志 + 敏感数据脱敏 |
| 认证 | `_auth_headers()` 使用 `PRIVATE-TOKEN`（GitCode PAT） |
| Issue CRUD | `_create_issue()` / `_get_issue()` / `_patch_issue()` / `_delete_issue()` |
| PR CRUD | `_create_pr()` / `_get_pr()` / `_pr_labels()` / `_post_pr_comment()` |
| Bot 检测 | `_bot_comments_since()` — 按机器人 login + 时间戳过滤评论 |
| 资源收集 | `_created_issue_numbers` 全局列表，会话结束时批量清理 |

### `conftest.py`（3 个 fixture）

1. **`_capture_case_id`**（autouse）：打印 `[CASE START/END]` banner，设置 `_current_case_id`
2. **`_cleanup_created_issues`**（session, autouse）：会话结束批量删除所有创建的 Issue
3. **`my_login`**（session）：通过 `GET /user` 获取当前 token 持有者 login

### Webhook 等待模式

```python
time.sleep(WAIT_AFTER_WEBHOOK)  # 12-15 秒，等待机器人处理
comments = _bot_comments_since(issue_number, since_iso=before_ts)
assert any("assigned" in c.lower() for c in comments)
```

## CI/CD 集成

### `ci.yml` — 标准测试运行器

- **触发**：push 到 `main`、PR 到 `main`、`workflow_dispatch`
- **环境**：ubuntu-latest, Python 3.11
- **执行**：`bash services/<service>/<community>/run_all.sh`

### `refine-on-comment.yml` — AI 驱动测试设计审查（核心）

这是仓库中**最复杂的工作流**，实现了自动化 TSE（测试工程师）审查循环：

```
PR 包含 TestStrategy.md / test_cases.py（draft PR）
    │
    ▼
[1] 定位 PR 中的测试交付物
    │
    ▼
[2] 统计 [auto-revise] 提交轮次（最多 3 轮）
    │
    ▼
[3] 从 agent-development-specification 仓库下载 TSE Agent 规范
    │
    ▼
[4] opencode run + TSE Agent 审查 → .review-verdict.md
    │
    ├─ VERDICT: PASS → gh pr ready + gh pr merge（自动合并）
    │
    └─ VERDICT: FAIL
        ├─ 轮次 < 3 → Integration-Test-Agent 自动修订 → commit [auto-revise] → 重触发
        └─ 轮次 ≥ 3 → 评论"测试设计不合格，请重新设计提交" → 拒绝
```

**防循环机制**：
- `[auto-revise]` 提交标签计数
- 3 轮上限
- `persist-credentials: false` + PAT 覆盖 GITHUB_TOKEN
- `cancel-in-progress: false`

**运行器**：`self-hosted, ai-dev-runner`
**LLM**：`alibaba-cn/glm-5` via opencode CLI

## AI 测试技能（`test_skills_base/`）

### `test-case-generator` — 测试用例生成 Agent

- **输出模式**：Markdown（8 字段表格 + `agent-exec` YAML）或 Python（pytest 函数）
- **覆盖维度**：9 个必检维度 — 正常流、异常、边界值、空值、特殊字符、权限、数据唯一性、重复操作、异常输入
- **关键创新**：每条用例包含 `agent-exec` 代码块（YAML），描述精确的 API 调用 / Playwright 动作 + 断言，使用例可被人和 AI Agent 双重执行

### `test-case-execution-assistant` — 测试执行 Agent

- **输入**：结构化测试用例
- **执行方式**：curl/Bash（API）或 Playwright（UI）
- **输出**：7 列执行报告（ID / 前提条件 / 步骤 / 实际结果 / 预期结果 / 状态 / 缺陷描述）
- **状态**：Pass / Fail / Blocked / Not Executed
- **边界**：只执行，不设计或修改测试用例

## 在 ai-flow 五阶段中的位置

```
Phase A: 需求分析        → 无测试
Phase B1: 开发预览       → tester Agent 冒烟测试（在业务仓库内）
Phase B2: 开发提交       → ★ integration-tests 门禁（集成测试 + TestStrategy 审查）
Phase C: 测试发布        → ★ integration-tests 集成测试执行
Phase D/E: 正式上线      → 回归测试
```

### 工作流程

1. **测试设计**：AI Agent（Integration-Test-Agent）根据需求生成 `TestStrategy.md` + `test_cases.py`
2. **提交 Draft PR**：提交到 `services/<module>/` 目录
3. **自动审查**：`refine-on-comment.yml` 中的 TSE Agent 审查质量
4. **自动修订**：不合格则 AI 自动修订（最多 3 轮）
5. **合并**：审查通过自动合并到 `main`
6. **执行**：合并后通过 `ci.yml` 或手动 `run_all.sh` 执行

## 关键模式总结

| 模式 | 说明 |
|------|------|
| 多社区架构 | `base_community/` + `*_community/`，共享用例 + 社区特定用例 |
| Webhook 等待 | `time.sleep(12-15s)` + 时间戳过滤机器人评论 |
| 会话清理 | 全局收集创建的资源，session fixture 批量删除 |
| HTTP 日志 | 每次请求/响应记录到 `.jsonl`，按用例 ID 关联 |
| AI 闭环 | 生成→审查→修订→合并→执行，全程 AI 驱动 |

---

## 🔗 相关笔记

- [[概览]] — 基础设施总览
- [[服务间调用关系]] — 调用关系
- [[2026-06-16-forum-reply-robot-pr113-unit-test-fail]] — 单测门禁故障

> 索引：[[基础设施]] · 返回 [[首页]]
