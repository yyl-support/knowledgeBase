---
tags:
  - 服务
  - 中台类
  - APIMagic
---

# 中台类 — APIMagic 数据统计 API 平台

> 仓库：`opensourceways/APIMagic`（私有）
> 分析时间：2026-06-21
> 语言：Java (Spring Boot) + MagicScript (.ms)
> 地址：https://github.com/opensourceways/APIMagic

## 仓库定位

基于 **MagicAPI 低代码框架**的 HTTP API 快速开发平台，是 opensourceways 生态的**集中式数据统计 API 层**。无需传统 Java 分层（Controller/Service/Dao/Mapper/XML/VO），所有 API 端点以 `.ms`（MagicScript）脚本定义，存储在 PostgreSQL 中，由 MagicAPI 引擎运行时加载并自动映射为 HTTP 路由。

**规模**：**275 个端点**，横跨 **38 个业务分组**，全部为只读查询接口。

## 技术栈

| 组件 | 版本/详情 |
|------|----------|
| Java | Spring Boot 2.6.6 |
| MagicAPI | 2.1.0 (`magic-api-spring-boot-starter`) |
| 数据库 | PostgreSQL (驱动 42.7.11, 连接池 Alibaba Druid 1.2.1) |
| 缓存 | Redis (Jedis 4.4.3) |
| 构建 | Maven → `magic-api-demo.jar` |
| API 文档 | Swagger 2 (springfox 2.9.2 + magic-api-plugin-swagger 2.0.2) |
| 容器基础 | `openeuler/openeuler:22.03-lts` + OpenJDK 11 |
| 脚本语言 | MagicScript (.ms) — 类 JavaScript 语法 + Java 互操作 |

## 目录结构

```
APIMagic/
├── magic-api/
│   ├── api/                    # 275 个 API 端点定义（.ms 文件）
│   │   ├── SIG/                # SIG 相关 API（12 端点）
│   │   ├── datastat/           # 旧版数据统计（34 端点）
│   │   ├── datastat-new/       # 新版数据统计（16 端点）
│   │   ├── 通用查询/            # 通用查询引擎（30 端点）
│   │   ├── 项目总览看板/        # 项目总览看板（26 端点）
│   │   ├── 社区下载/            # 社区下载统计（16 端点）
│   │   └── ...（38 个分组）
│   └── function/
│       └── 工具函数/            # 共享工具函数（日期转换、用户账号获取）
├── src/main/java/.../
│   ├── MagicAPIExampleApplication.java    # Spring Boot 入口
│   ├── configuration/
│   │   └── MagicAPIConfiguration.java     # 多数据源、自定义 Bean
│   └── interceptor/
│       ├── SimpleAuthorizationInterceptor.java    # MagicAPI UI 认证
│       └── UpdatePermissionInterceptor.java       # API 权限拦截器
├── scripts/
│   ├── python/                 # 工具脚本（导入/导出/文档生成/表替换）
│   └── shell/                  # 校验脚本（groupId 一致性）
├── docs/
│   ├── api/                    # API 文档（自动生成 + 手写模板）
│   ├── 权限判定方案.md          # 权限设计文档
│   └── table-replace-feature.md # 表替换风险分析
├── test/                       # 自动化测试（Python runner + JSON spec）
├── .claude/skills/             # AI 技能（API 模板 + SQL 安全审计）
├── Dockerfile                  # 多阶段构建（openEuler 22.03）
├── Makefile                    # 开发者工作流命令
├── API_LIST.md                 # 自动生成的 API 清单（275 条）
└── api_consumers.json          # API 消费方追踪
```

## API 分组全览（38 组 / 275 端点）

| 分组 | 端点数 | 用途 |
|------|:------:|------|
| **datastat** | 34 | 旧版数据统计（SIG 贡献、开发者页面、TC 成员、配置管理） |
| **通用查询** | 30 | 通用查询引擎（Issue/PR/Forum/用户/企业/贡献分页查询） |
| **项目总览看板** | 26 | 项目看板（CI 构建、clone 数据、PR 趋势、审阅 PR、社区热点） |
| **datastat-new** | 16 | 新版数据统计（SIG/开发者/社区贡献/数据总览） |
| **社区下载** | 16 | 下载统计（总量/趋势/版本/地理分布/来源分布） |
| **开源技术雷达** | 15 | 开源技术评估（GitHub Stars/OSSF/排名/雷达图/趋势） |
| **资源** | 14 | 资源管理（CPU/NPU/Workflow/集群/费用趋势） |
| **SIG** | 12 | SIG 指标（活跃度/成员/仓库/贡献者排名/运作情况） |
| **社区运营质量** | 12 | 运营质量（Issue 指标/用户留存/严重缺陷/论坛指标） |
| **开发者** | 10 | 开发者统计（海外贡献者/CLA/周月环比/活跃用户/趋势） |
| **健康度** | 8 | 社区健康（趋势/同比/大象企业/季度均值/指标类型） |
| **数据入湖** | 8 | 数据湖（comment/commit/issue/PR 分页 + 组织/仓库配置） |
| **服务分析** | 7 | 服务分析（旭日图/矩阵图/直方图/趋势/环比） |
| **自定义看板接口** | 7 | 自定义看板（指标/筛选器/角色贡献/详情） |
| **指标字典** | 6 | 指标字典（字典/总数/详情/列表/模型/社区配置） |
| **服务看板** | 6 | 服务看板（PV/UV/服务列表/指标/趋势/字典） |
| **开源实习** | 5 | 开源实习（导师/学生贡献/领题人数/详情） |
| **软件包维护情况** | 5 | 软件包维护（CVE 详情/层级维护率/版本/维护率同比） |
| **会议** | 4 | 会议管理（参会人/预定查询/组织列表/成员信息） |
| **社区** | 4 | 社区核心（社区列表/组织架构/组织成员/开源项目数据） |
| **ascend-sig-info** | 3 | Ascend SIG（Reviewers/BranchKeeper/FileApprovers） |
| **mindspore-sig** | 3 | MindSpore SIG 信息 |
| **openubmc** | 3 | OpenUBMC（committer/maintainer 信息） |
| **仓库** | 3 | 仓库指标（CLOC/分支详情/总数） |
| **年报** | 3 | 年报（实习/个人报告/月度贡献） |
| **总览** | 3 | 总览（健康度指标/年度对比/交叉对比） |
| **文档体验模型** | 3 | 文档评价（评分/详情/雷达图） |
| **服务健康检查** | 3 | 健康检查（healthz/reload/权限） |
| **AIdemo** | 2 | AI/GPT 演示（聊天状态/线程查询） |
| **影响力** | 2 | 影响力排名（DistroWatch/DB-Engines） |
| **组织** | 2 | 组织统计（CLA 签署组织总数/组织总数） |
| **AI统计** | 6 | AI 统计（SIG/代码类型/工具/开发者/概览/趋势） |
| **openubmc-sig** | 1 | OpenUBMC SIG 详情 |
| **下载** | 1 | 软件包下载 |
| **用户贡献详情** | 1 | 用户贡献总数 |
| **邮件发送** | 1 | 邮件发送 |

## MagicScript (.ms) 文件结构

每个 `.ms` 文件由**JSON 元数据头**和**脚本体**两部分组成：

```
{ JSON 元数据（路由、参数、校验、响应 schema） }
================================
<MagicScript 脚本体>
```

### JSON 元数据头

```json
{
  "id": "UUID",
  "groupId": "父组 UUID",
  "path": "/path/to/api",
  "method": "GET|POST",
  "parameters": [
    {
      "name": "community",
      "validateType": "pattern",
      "expression": "^[a-zA-Z]{1,32}$",
      "error": "无效的社区参数"
    }
  ],
  "requestBodyDefinition": { "children": [...] },
  "responseBodyDefinition": { ... },
  "options": [
    { "name": "permission", "value": "datastat,mcp" }
  ]
}
```

### 脚本体（MagicScript）

```javascript
import java.time.Instant
import response

var community = path.community
var sql = """
  SELECT count(*) as total
  FROM sig_info
  <where>
    <if test="community != null and community != ''">
      AND community = #{community}
    </if>
  </where>
"""
return db.select(sql)
```

**核心特性**：
- `#{}` — 参数化值（安全，防注入）
- `${}` — 结构化标识符（需白名单校验）
- MyBatis 风格 XML 标签（`<if>` / `<where>` / `<foreach>`）
- Java 类导入（`import java.time.Instant`）
- 内置模块（`db` / `http` / `response` / `request`）

## 安全模型

### 权限拦截器（`UpdatePermissionInterceptor`）

```
API 请求到达
    │
    ├─ 无 permission 配置 → 直接放行（大部分只读接口）
    │
    └─ 有 permission 配置 → 分发校验
        │
        ├─ "datastat" → Cookie _Y_G_ → Manager Token → 用户权限 API → 权限匹配
        │
        ├─ "datastat" + "admin" → 额外 datastat_admin 检查
        │
        ├─ 自定义权限（如 "mcp"）→ 请求头 vs 配置密钥比对
        │
        └─ 多权限 V2（逗号分隔，如 "datastat,mcp"）→ 任一通过即可
```

**返回码**：401（未登录）/ 403（无权限）/ 500（系统错误）/ null（放行）

### API 级别权限

每个 `.ms` 文件的 `options` 中可设置 `permission`：

```json
{ "name": "permission", "value": "datastat,mcp" }
```

## 构建与部署

### Dockerfile（多阶段）

1. **Builder**：`openeuler/openeuler:22.03-lts` + OpenJDK 11 + Maven → `mvn clean package -DskipTests`
2. **Runtime**：OpenJDK 11，非 root 用户 `magic`（UID 1000），暴露 8080，外部配置 `/home/magic/config/application.yml`

### Makefile 核心命令

| 命令 | 用途 |
|------|------|
| `make export` | 从 DB 导出 .ms 到本地 |
| `make insert` | 本地 .ms 插入/更新到 DB |
| `make api-list` | 生成 API_LIST.md |
| `make api-add API_PATH=... CONSUMER=...` | 追踪 API 消费方 |
| `make replace TABLE=...` | 原子表替换（含敏感数据注入） |
| `make rollback TABLE=...` | 回滚到上一版本 |

### 运营模型

```
.ms 脚本定义 → make insert 插入 PostgreSQL
    → MagicAPI 引擎启动时加载 → 缓存在内存
    → HTTP 路由自动映射 → 对外提供服务
    → 更新需 make insert + 重启 或 /check/reload（特权接口）
```

## CI/CD 工作流

| 工作流 | 触发条件 | 用途 |
|--------|---------|------|
| `gate-check.yml` | PR opened/synced | 移除 `gate_check_pass` 标签 → 执行 CodeArts 流水线 → 通过后打标签 |
| `check-label-owner.yml` | PR labeled | 确保 `gate_check_pass` 只能由 `opensourceways-robot` 添加 |
| `pr-branch-check.yml` | PR opened/synced | 分支规范：main ← release/*, release/* ← feature/*/bugfix/* |

## API 文档体系

### 结构

```
docs/api/
├── README.md          # 概览（模仿 GitHub REST API 文档风格）
├── _TEMPLATE.md       # 单端点文档模板
├── community.md       # 手工范例（含真实响应数据）
└── group-*.md         # 自动生成的分组文档（275 端点）
```

### 统一响应封装

```json
{
  "code": 1,            // 1=成功, 0=参数错误, -1=内部错误
  "message": "success",
  "data": {},
  "timestamp": 1779097608026,
  "executeTime": 1      // ms
}
```

### 文档生成

`scripts/python/gen_api_docs.py` 自动从 `.ms` 文件头提取参数、校验规则、响应字段和示例数据，生成 `docs/api/group-*.md`。生成时自动脱敏（邮箱 → `<email>`，公司名 → `<xx>`）。

## AI 技能（`.claude/skills/`）

### `ms-api-template` — 新建 API 模板

- **触发**：「新建接口」「创建 API」
- **提供**：GET/POST 模板、group 发现流程、常用 SQL 模式（聚合/JOIN/分页/时间戳/UNION）
- **安全规则**：值用 `#{}`，标识符 `${}` 需白名单；返回不要包 `{code, data}`（引擎自动封装）

### `ms-sql-security` — SQL 安全审计

- **触发**：「审计 ms 文件」「修复 SQL 注入」
- **覆盖 6 种漏洞**：WHERE 值用 `${}`、JSONB 拼接、ORDER BY 无白名单、动态列名无枚举、硬编码 Token、INTERVAL 字符串拼接

## 测试基础设施

### 自动化测试（`test/`）

- **运行器**：`_runner.py` — 读取 JSON spec，执行 curl，校验响应
- **配置**：`APIMAGIC_BASE_URL` 环境变量（默认 `http://localhost:9999`）
- **Spec 格式**：

```json
{
  "endpoint": "/server/query/xxx",
  "method": "POST",
  "cases": [
    {
      "name": "normal_params",
      "params": { ... },
      "expected_code": 1,
      "expected_data_type": "dict",
      "expected_data_fields": ["field1"],
      "max_response_time_ms": 500
    }
  ]
}
```

**校验项**：响应 code、数据类型、字段存在性（顶层 + 嵌套列表项）、空列表检查、响应时间限制

## 消费方关系

APIMagic 作为数据统计中台，被多个前台系统消费：

```
消费方（多个前台系统）
├── openEuler 社区看板
├── Ascend 看板
├── CANN 社区看板
├── MindSpore 看板
├── openUBMC 看板
├── 管理后台
└── 第三方集成
        │
        ▼
APIMagic (275 API)
        │
        ▼
PostgreSQL
```

**消费方追踪**：`api_consumers.json` 映射 API 路径 → 消费系统列表

## 与 opensourceways 生态的关系

| 维度 | 说明 |
|------|------|
| 数据来源 | PostgreSQL（聚合自 Gitee/GitHub 的 PR/Issue/Commit/Comment + 用户注册 + 下载日志 + 会议记录 + SIG 数据） |
| 服务角色 | **只读查询层** — 不修改数据，只暴露统计聚合 |
| 服务多社区 | openEuler / openGauss / MindSpore / CANN / openUBMC / vllm 等 20+ 社区 |
| 部署方式 | Dockerfile 构建 → SWR 推送 → ArgoCD 同步 → K8s 部署 |
| AI 开发 | 通过 backlog ai-flow 管理，`.ai-flow/services/` 中有对应 YAML 配置 |

---

## 🔗 相关笔记

- [[中台类]] — 中台类概述
- [[README]] — 组织总览

> 索引：[[服务总览]] · 返回 [[首页]]
