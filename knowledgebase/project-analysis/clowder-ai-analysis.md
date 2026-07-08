# Clowder AI 架构分析

## 一、整体软件架构

### 1.1 三层架构原则

Clowder AI 采用**三层分离架构**，明确界定每层的职责边界：

| 层级 | 负责内容 | 不负责内容 |
|------|----------|------------|
| **Model（模型层）** | 推理、生成、理解、创造力 | 长期记忆、协作纪律、审计 |
| **Agent CLI（代理层）** | 工具调用、文件操作、命令执行 | 团队协调、跨模型 review |
| **Platform（平台层）** | 身份管理、协作协议、治理门禁、审计追踪 | 推理（这是模型的工作） |

**核心理念**：
> *Models set the ceiling. The platform sets the floor.*
> 模型决定上限，平台决定下限。每一层是乘法关系，不是加法。

### 1.2 技术栈结构

```
clowder-ai/
├── packages/
│   ├── web/          # React + Zustand 前端（Hub UI）
│   │   ├── Workspace（对话/监控/知识/导航）
│   │   ├── Rich Block 结构化呈现
│   │   └── WebSocket 实时 bubble stream
│   │
│   ├── api/          # Fastify API 服务器（核心业务逻辑）
│   │   ├── domains/cats/services/    # 核心领域服务
│   │   ├── infrastructure/           # 基础设施（WebSocket/调度器等）
│   │   └── routes/                   # HTTP 路由
│   │
│   ├── shared/       # 共享类型定义和工具函数
│   │
│   └── mcp-server/   # MCP（Model Context Protocol）服务器
│       ├── cat-cafe（核心工具）
│       ├── cat-cafe-collab（协作工具）
│       ├── cat-cafe-memory（记忆工具）
│       └── cat-cafe-signals（信号工具）
│
├── docs/             # 真相源文档（ADR、feature specs、lessons）
│
├── cat-cafe-skills/  # Skills 框架（按需加载的 prompt 模块）
│
└── scripts/          # 运维脚本（安装、启动、备份等）
```

### 1.3 存储层架构

| 存储 | 端口 | 用途 | 特殊规则 |
|------|------|------|----------|
| **Redis 6399** | 生产端口 | runtime/用户数据 | **神圣不可删除（Iron Law #1）** |
| **Redis 6398** | 隔离端口 | worktree/alpha/test 环境 | 可清理 |
| **SQLite** | 本地文件 | evidence.sqlite 记忆索引 | 编译层，可重建 |
| **docs/** | 文件系统 | 真相源文档 | 唯一权威来源 |
| **git** | 版本库 | 版本控制/审计追踪 | 不可篡改历史 |

### 1.4 核心领域模块（API 层）

```
packages/api/src/domains/cats/services/
│
├── agents/                    # Agent 管理核心
│   ├── registry/              # Agent 注册表
│   │   └── AgentRegistry.ts   # 猫猫身份注册
│   │
│   ├── routing/               # 路由系统（核心）
│   │   ├── AgentRouter.ts             # 主路由器
│   │   ├── a2a-mentions.ts             # A2A @mention 解析
│   │   ├── MultiMentionOrchestrator.ts # 多猫编排
│   │   ├── route-parallel.ts           # 并行思考路由
│   │   ├── route-serial.ts             # 串行执行路由
│   │   └── cat-target-resolver.ts      # 猫目标解析
│   │
│   ├── invocation/            # 调用队列系统
│   │   ├── InvocationQueue.ts          # 统一 FIFO 队列
│   │   ├── QueueProcessor.ts           # 队列处理器
│   │   ├── InvocationTracker.ts        # "谁在跑"追踪
│   │   └── SessionMutex.ts             # Session 互斥锁
│   │
│   └── providers/             # 模型适配层
│       ├── ClaudeAgentService.ts       # Claude CLI 适配
│       ├── CodexAgentService.ts        # GPT/Codex CLI 适配
│       ├── GeminiAgentService.ts       # Gemini CLI 适配
│       ├── OpenCodeAgentService.ts     # opencode CLI 适配
│       ├── KimiAgentService.ts         # Kimi API 适配
│       ├── A2AAgentService.ts          # Agent 间通信桥接
│       └── acp/                        # ACP 协议适配
│
├── session/                   # Session 管理
│   ├── SessionManager.ts      # Session 生命周期
│   └── SessionBootstrap.ts    # 窄口上下文注入
│
├── collaboration/             # 协作服务
│   └── reviewer-matcher.ts    # Review 匹配（跨族 review）
│
├── orchestration/             # 编排服务
│   ├── TaskExtractor.ts       # 任务提取
│   └── AutoSummarizer.ts      # 自动摘要
│
├── stores/                    # 存储抽象层
│   ├── redis/                 # Redis 实现
│   ├── memory/                # 内存实现（测试用）
│   └── ports/                 # 接口定义（依赖反转）
│
└── stores/factories/          # 存储工厂
```

### 1.5 Harness Engineering 六+一构件

Clowder 实现了行业公认的六大 Agent Harness 构件，并新增第七类：

| 构件                             | Clowder 实现                                 | 外部概念锚点            |
| ------------------------------ | ------------------------------------------ | ----------------- |
| **1. Durable State**           | docs/ 真相源、evidence.sqlite、Thread/Task      | OpenAI state      |
| **2. Plans & Decomposition**   | feat-lifecycle、Design Gate、writing-plans   | Anthropic plans   |
| **3. Feedback Loops**          | lint/test/gate/CI、跨族 review、Magic Words    | Fowler loops      |
| **4. Legibility**              | search_evidence、Hub 明厨亮灶、InvocationTracker | Thoughtworks      |
| **5. Tool Mediation**          | MCP + Skills、SystemPromptBuilder           | OpenAI tools      |
| **6. Entropy Control**         | F163 知识生命周期、Build to Delete、ADR-031 Sunset | Anthropic entropy |
| **7. Collaboration Semantics** | @路由、targetCats、球权状态机、统一执行平面                | **Clowder 独有**    |

---

## 二、模型间通信机制

### 2.1 通信流程概览

```
用户消息 → @mention 解析 → InvocationQueue 入队
    → QueueProcessor 取出 → AgentRouter 路由
    → Provider Adapter 执行 → 模型 CLI/API
    → 输出解析 → A2A mention 检测 → 下一轮调用
```

### 2.2 核心组件详解

#### ① InvocationQueue（统一调用队列）

**职责**：Per-thread, per-user FIFO 队列，管理所有调用请求。

**关键属性**：
```typescript
interface QueueEntry {
  id: string;
  threadId: string;
  userId: string;
  content: string;              // 消息内容
  targetCats: string[];         // 目标猫列表
  source: 'user' | 'connector' | 'agent';
  intent: string;               // 'ideate' | 'execute'
  status: 'queued' | 'processing';
  priority: 'urgent' | 'normal';
  autoExecute: boolean;         // 自动执行标志
  callerCatId?: string;         // A2A 来源猫
}
```

**特点**：
- 与 InvocationTracker 互补：Queue = "谁在等"，Tracker = "谁在跑"
- 支持 F175 消息合并（相邻同源同目标消息自动合并）
- 最大队列深度 = 5，防止消息堆积

#### ② AgentRouter（路由核心）

**职责**：解析 @mention，路由到正确的 Agent Service。

**路由规则**：

| 场景 | 路由策略 |
|------|----------|
| 有 @mention | 路由到指定猫 + 更新对话参与者 |
| 无 @mention（有历史） | Fallback 到最近回复的猫（F078） |
| 无 @mention（新对话） | 默认路由到布偶猫（opus） |
| @all / @全体 | 广播到所有可用猫 |
| ideate intent + 多猫 | **并行独立思考**（routeParallel） |
| execute intent 或单猫 | **串行执行**（routeSerial） |

**关键代码路径**：
- `packages/api/src/domains/cats/services/agents/routing/AgentRouter.ts`
- `resolveCatTarget()` → 解析猫目标
- `routeParallel()` → 多猫并行思考
- `routeSerial()` → 单猫串行执行

#### ③ A2A Mentions（Agent 间通信协议）

**职责**：从猫回复文本中检测对其他猫的 @mention，触发下一轮调用。

**解析规则（F046 简化）**：

```
1. 剥离围栏代码块（```...```）后再解析
2. 仅匹配行首 mention（可带前导空白）→ 直接路由，无需动作词
3. 长匹配优先 + token boundary，避免 @opus-45 误命中 @opus
4. 过滤自调用（不能 @自己）
5. 最大 A2A 链深度 = 15（MAX_A2A_DEPTH）
6. 最大 mention 目标数 = 2（MAX_A2A_MENTION_TARGETS）
```

**示例**：
```
# 行首 mention = 直接路由
@codex 请帮我 review 这段代码

# 非行首 mention = 不触发路由（只是引用）
我觉得 @opus 之前的设计有问题，但这次我会自己处理。
```

**Ping-Pong Breaker（乒乓熔断）**：

检测无限乒乓对话：
```
猫 A: "@猫B 你觉得怎么样？"
猫 B: "@猫A 我觉得可以。"    ← 无 tool call
猫 A: "@猫B 再看看？"         ← 无现实动作
                          🛑 熔断！
```

熔断条件：连续无 tool call 的纯文字互 @。

#### ④ MultiMentionOrchestrator（多猫协作编排）

**职责**：管理多猫 mention 请求的状态机。

**状态机**：
```
pending → running → partial → done
                   ↘ timeout
```

**关键属性**：
```typescript
interface MultiMentionRequest {
  id: string;
  threadId: string;
  initiator: CatId;           // 发起猫
  callbackTo: CatId;          // 回调猫（完成后通知）
  targets: CatId[];           // 目标猫列表
  question: string;           // 问题
  timeoutMinutes: number;     // 超时时间
  status: MultiMentionStatus;
}
```

**流程**：
```
猫 A 发起 multi_mention → targets: [猫 B, 猫 C]
→ 猫 B、猫 C 并行执行
→ 各返回 response
→ 收齐 → callbackTo 猫 A → 猫 A 继续处理
```

#### ⑤ Provider Adapters（模型适配层）

**职责**：将统一消息格式转换为各模型 CLI/API 的输入格式，解析输出。

| Adapter              | 模型                         | 输入格式              | 输出格式        | MCP 支持        |
| -------------------- | -------------------------- | ----------------- | ----------- | ------------- |
| ClaudeAgentService   | Claude (Opus/Sonnet/Haiku) | stream-json       | stream-json | ✅ 原生          |
| CodexAgentService    | GPT / Codex                | json              | json        | ✅ 原生          |
| GeminiAgentService   | Gemini                     | stream-json / ACP | stream-json | ✅ CLI-managed |
| OpenCodeAgentService | 多模型                        | ndjson            | ndjson      | ✅ 原生          |
| KimiAgentService     | Kimi                       | API               | API         | ❌ 回调桥接        |
| A2AAgentService      | Agent 间                    | 内部格式              | 内部格式        | -             |

**ACP 协议适配**：
```
providers/acp/
├── AcpClient.ts           # ACP 客户端
├── GeminiAcpAdapter.ts    # Gemini ACP 适配
├── AcpProcessPool.ts      # 进程池管理
└── acp-event-transformer.ts  # 事件转换
```

### 2.3 球权流转机制

**核心概念**：球权（ball ownership）= 当前执行权的归属。

**流转示例**：
```
时间 →

铲屎官  ──● "做 F183"
         │
         ↓
Ragdoll  ──●━━━━━━━━━━●─────────────────●
         │ 接球       │ git commit      │ @codex
         │ (开始执行) │ (现实动作 ✓)    │ targetCats
         │            │                 │
         ↓            │                 ↓
Maine    ───────────────────────────────●━━━━━━●
Coon                                 │ 接球  │ verdict
                                      │ 读代码│ pass
                                      │ 跑测试│ (现实动作 ✓)
                                      │       ↓
Ragdoll  ─────────────────────────────────────●━━━━━ merge
```

**核心规则**：

| 规则 | 说明 |
|------|------|
| ✓ = 现实动作 | tool call / git commit / review verdict / MCP call |
| 状态迁移必须有现实动作 | 纯文字声明不算状态迁移 |
| Shared State | 所有猫读写同一份 Thread/Task/Evidence，不靠消息传话 |
| 接/退/升三选一 | 球权状态机的三个分支 |

### 2.4 统一执行平面

**设计目标**：所有调用（user/agent/multi_mention）统一入队，统一处理。

```
Unified Execution Plane
├── InvocationQueue
│   ├── user 消息
│   ├── connector 消息（飞书/Telegram）
│   └── agent @mention（A2A handoff）
├── QueueProcessor
│   ├── 自动执行
│   ├── 暂停/恢复
│   └── 取消
├── InvocationTracker
│   ├── 谁在跑
│   ├── 谁在等
│   └── 谁完成
└── SessionBootstrap
    ├── 窄口上下文注入
    ├── task snapshot
    └── recall 指令
```

### 2.5 Session Bootstrap（窄口上下文注入）

**问题**：模型上下文窗口有限，不能每次塞入所有历史。

**解决方案**：窄口注入 = 精选必要上下文。

**注入层级**：

| 层级 | 时机 | 内容 |
|------|------|------|
| Session-level（静态身份） | new / compressed / changed | CLAUDE.md 身份、shared-rules 家规、队友名册 |
| Per-invocation（动态上下文） | 每次 invocation | A2A 球权状态、voice mode、SOP 阶段 |
| Session #2+（冷启动） | 有前序 session 时 | 上一轮摘要、任务快照、recall 指令 |
| Runtime hooks（执行中） | tool call 前后 | sanctuary guard、evidence guard |
| Post-execution（回收） | 执行完毕后 | mention 检测、rich block 提取 |

### 2.6 跨厂商多样性（结构性纠错）

**核心理念**：不同模型看同一件事会发现不同问题。

```
🧶 毛线球（球权）
├── Ragdoll 布偶 · Claude · IDE+蓝图
├── Maine Coon · GPT · 放大镜+✓
└── Siamese 暹罗 · Gemini · 画板+调色
```

**应用场景**：

| 场景 | 用法 |
|------|------|
| Cross-Model Review | Claude 写代码 → GPT review |
| 愿景守护 | 第三猫检查是否偏离初衷 |
| 并行思考 | 同一问题 → 多猫独立思考 → 汇总 |
| CVO 终裁 | 人做最终决策，AI 不越权 |

---

## 三、Iron Laws（铁律）

四条不可违背的承诺：

| 铁律 | 含义 |
|------|------|
| **"We don't delete our own databases."** | Redis 6399 是神圣不可侵犯的圣域 |
| **"We don't kill our parent process."** | 不自杀、不杀父进程 |
| **"Runtime config is read-only to us."** | 配置修改需人工操作 |
| **"We don't touch each other's ports."** | 端口隔离，互不干扰 |

---

## 四、关键文件路径索引

| 功能 | 文件路径 |
|------|----------|
| 主路由器 | `packages/api/src/domains/cats/services/agents/routing/AgentRouter.ts` |
| A2A mention 解析 | `packages/api/src/domains/cats/services/agents/routing/a2a-mentions.ts` |
| 多猫编排 | `packages/api/src/domains/cats/services/agents/routing/MultiMentionOrchestrator.ts` |
| 调用队列 | `packages/api/src/domains/cats/services/agents/invocation/InvocationQueue.ts` |
| 队列处理器 | `packages/api/src/domains/cats/services/agents/invocation/QueueProcessor.ts` |
| Session 管理 | `packages/api/src/domains/cats/services/session/SessionManager.ts` |
| Claude 适配 | `packages/api/src/domains/cats/services/agents/providers/ClaudeAgentService.ts` |
| Codex 适配 | `packages/api/src/domains/cats/services/agents/providers/CodexAgentService.ts` |
| Gemini 适配 | `packages/api/src/domains/cats/services/agents/providers/GeminiAgentService.ts` |
| 架构文档 | `docs/architecture/2026-05-05-architecture-views.md` |
| 协作协议 | `docs/decisions/002-collaboration-protocol.md` |

---

## 五、总结

Clowder AI 的核心创新在于：

1. **三层分离**：明确界定 Model、Agent CLI、Platform 的职责边界
2. **统一执行平面**：所有调用（user/agent/multi_mention）统一入队处理
3. **球权协议**：状态迁移必须有现实动作，防止乒乓对话
4. **跨厂商多样性**：不同模型看同一件事 = 结构性纠错来源
5. **Shared State**：所有猫读写同一份状态，不靠消息传话
6. **Harness 自演化**：规则自带删除条件，防止只增不减

这不是一个简单的多模型调用框架，而是让多个 AI Agent 形成真正协作团队的**平台层**。