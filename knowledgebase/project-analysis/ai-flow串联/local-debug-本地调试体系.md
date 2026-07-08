---
tags:
  - ai-flow
  - 调试
  - 本地
---

# local-debug 本地调试体系

## 概述

`docs/local-debug/` 是 backlog ai-flow 的**本地调试工具集**。它的设计核心理念是**薄包装（Thin Wrapper）**——不复刻任何业务逻辑，只准备环境，然后**直调你本地 backlog 仓里真正的 `orchestrate.sh` / `gates` / `tests` / jenkins 脚本**。

### 它解决什么问题

在线上跑 AI Flow 链路最短需要几十分钟，如果脚本有 bug 或配置有问题，修一次等一次，效率极低。本地调试器让你在 **push 之前** 就在本机验证改动，几分钟见分晓。

### 调什么和怎么调

| 你要调的东西 | 用哪个调试器 | 验证通过后如何生效到远端 |
|-------------|------------|----------------------|
| 改了 `orchestrate.sh` / `gates` / 脚本 | issue-2 调试器 | 手动 `git push` 到 backlog 仓库 |
| 改了 `services/<服务>.yaml` 配置 | issue-3 调试器 | 同上 |
| 要验证 AI 能否正确生成设计/代码 | issue-2 调试器 | `submit` 自动 push + 开 PR 到 umbrella 仓库 |
| 架构设计已合入，要验证测试用例质量 | test 调试器 | 手动提交 Test 交付件到 backlog |

---

## 完整使用流程：从本地调试到远端生效

```
本地调试 → 远端生效 全流程
────────────────────────────

① 本地修改 backlog 仓的脚本
   改了 .ai-flow/src/orchestrate.sh / scripts/ / services/ 等

② 本地验证
   bash docs/local-debug/local-debug.sh setup <调试issue号> ...
   bash docs/local-debug/local-debug.sh design
   → 调试器用你本地改过的脚本跑，看到产物对不对

▼
③ 本地确认无误
   检查 ~/issue2-debug/ai/design.md / git diff / 终端输出

▼
④ 手动推送到远端（仅限 backlog 仓库）
   cd /你的/backlog/仓库
   git add .ai-flow/src/ scripts/ services/
   git commit -m "fix: 说明你的改动"
   git push origin main

▼
⑤ 远端 CI 自动用你的新脚本（零漂移的根基）
   GitHub Actions 触发 → rm -rf + 全新 clone → 拉到最新 main
   → 跑的就是你刚刚推的那份脚本

▼ (可选)
⑥ 远端确认
   对调试 issue 评论 /ai-develop-preview 触发线上跑
   看 Actions run 结果——和本地跑同一份逻辑 ✅
```

**核心原理**：线上 CI 每一步都是 `rm -rf $WORK_DIR && git clone`（全新拉取），所以你 push 到远端后，下一次触发就能拿到你的改动。

---

## 如何在调试时追加自己的提示词

> 以下命令都在终端/Git Bash 中运行（Windows 用户请用 Git Bash，不是 PowerShell）。

调试器没有 `--prompt` 参数，但你可以在 `setup` 之后手动注入指令给 AI agent。

### 方法一：往 issue.txt 末尾追加（推荐）

`setup` 后、跑阶段前直接编辑：

```bash
# Mac/Linux
bash docs/local-debug/local-debug.sh setup 850 --umbrella om-datacenter \
  --gh-token-file ~/creds/github.txt --engine opencode

# 写入你的要求
cat >> ~/issue2-debug/ai/issue.txt <<'EOF'

--本轮用户要求--
把登录页按钮改成蓝色，右侧加一个"刷新"按钮。
sidebar 菜单项从 5 个精简到 3 个：首页、数据、设置。
EOF

bash docs/local-debug/local-debug.sh design
```

### 方法二：写 pr_feedback.md

```bash
echo "把登录按钮改成蓝色，加 loading" > ~/issue2-debug/ai/pr_feedback.md
bash docs/local-debug/local-debug.sh dev
```

`orchestrate.sh` 会把 `pr_feedback.md` 内容作为 `USER_FEEDBACK` 注入到 design 和 dev 的 prompt 中。注意后续每次 re-run 这个文件会被删除，需要重新写。

### 写法原则

| 效果差 | 效果好 |
|--------|--------|
| "优化一下页面" | "数据表格增加分页，每页 20 条" |
| "修 bug" | "点击提交按钮后没反应，需要弹出成功 toast" |
| "改样式" | "按钮色值改成 #3b82f6，hover 加深 10%" |

指令越具体，AI 跑偏概率越低。它拿到的就是你的原文，不会追问。

---

## 本地与线上分支的衔接机制

线上和本地使用**同一个分支名**，这是无缝衔接的关键：

- `orchestrate.sh` 的 `prime_branches()` 把分支固定为 `issue-{编号}-from-{默认分支名}`
- 例如 issue 785：分支名是 `issue-785-from-main`（如果仓库默认分支是 main）
- 线上 CI：`rm -rf + git clone`，拉到该分支最新代码
- 本地 `submit`：推送到同一个分支

```
本地 push 到 issue-785-from-main  →  线上 CI 全新 clone 同一分支  →  拿到你的最新代码
```

| 对比项 | 线上 CI | local-debug |
|--------|--------|------------|
| 获取代码 | **每次** `rm -rf` + 全新 `git clone` | setup 一次 clone，后续复用 |
| 分支名 | `issue-785-from-main`（自动计算） | 同上 |
| 代码来源 | 远端 issue-785-from-main 最新 | setup 那一刻的快照 |
| 如何刷新 | 自动 | `clean` 后重新 `setup`，或手动 `git pull` |

**重要**：本地 `dev`/`deploy`/`submit` 会真 push、真评论、真开 PR、真部署。务必使用单独创建的调试 issue。

---

## 三个调试器

| 调试器 | 脚本路径 | 对应工作流 | 覆盖阶段 | 前提条件 |
|--------|---------|-----------|---------|---------|
| issue-2 调试器 | `docs/local-debug/local-debug.sh` | Workflow Develop（开发预览+提交） | `setup` → `design` → `dev` → `deploy` → `run` → `submit` | 有 issue 号即可，不需要需求分析。`setup` 拉取的 issue.txt（标题+正文+评论）就是 AI agent 的全部上下文 |
| issue-3 调试器 | `docs/local-debug/local-debug-issue-3.sh` | Workflow Deploy Test（测试发布） | `setup` → `resolve` → `build` → `tagsync` → `verify` | issue 有 `project:<svc>` 标签即可，也不需要需求分析 |
| test 调试器 | `docs/local-debug/local-debug-test.sh` | 测试链路（测试设计 + 模块集成） | `setup` → `design` → `aggregate` | 需要该 issue 的架构设计文档已合入 main |

### 需求分析（issue-1）本地运行

虽然没有专门的调试器，但需求分析脚本是独立的，可以直接在终端跑：

```bash
cd /你的/本地/backlog/仓库

# 直接指定 issue 号运行（默认 dry-run，只看产物不 push）
bash .ai-flow/scripts/analyze_requirement.sh --issue-number 916

# 要发布（push 分支 + 开 PR）
bash .ai-flow/scripts/analyze_requirement.sh --issue-number 916 --publish
```

这个脚本不需要 clone umbrella、不需要 k8s、不需要 local-debug 的任何 setup。它只做三件事：
1. 拉取 issue 的标题+正文+评论
2. 拉取 spec 仓的需求分析模板和 agent 角色提示词
3. 调 AI 引擎（`claude` 或 `opencode`）生成需求分析说明书 + QA

**前提**：有 `GH_TOKEN`、装好了 `claude` 或 `opencode`。

> 注意：`issue-2` 调试器的 `design` 命令跑的是架构设计（产出 `design.md`），不是需求分析。它们调的不是同一个 agent。

### 各阶段运行要求

| 阶段 | 能用什么机器 | 需要什么工具 | 备注 |
|------|-------------|-------------|------|
| AI 改代码（design/dev） | Mac / Windows / Linux | `claude` 或 `opencode` | 引擎用 `--engine` 指定 |
| 真 k8s 预览部署（run --real-preview） | **仅 Linux 白名单** | `kubectl` + jenkins 凭据 | 非白名单机器自动降级为本地冒烟 |
| issue-3 确定性校验（resolve/tagsync） | Mac / Windows / Linux | `git` + `curl` + `python3` | 纯读 GitHub API + 本地计算 |
| docker 构建（build） | Mac（Docker Desktop）/ Linux | `docker` daemon | 仅打本地 tag=:dryrun，不推 |
| kubectl 校验现网（verify） | **仅 Linux 白名单** | `kubectl` + jenkins 凭据 | 只读操作 |
| test 生成（design/aggregate） | Mac / Windows / Linux | `claude` 或 `opencode` | 自动探测已装的引擎 |

> Windows 本机连 jenkins 会 `HTTP 418`（系统代理/未加白），这是环境限制，非脚本问题。

---

## 前置准备（三个调试器通用）

### 工具清单

| 工具 | 哪些阶段需要 | 备注 |
|------|-------------|------|
| `claude` 或 `opencode` | issue-2 的 `design`/`dev`，test 的全部 | 二选一，`--engine` 指定；`opencode` 默认模型 `alibaba-cn/glm-5` |
| `git` | 全部 `setup` | clone 仓库用 |
| `curl` | 全部 `setup` | 调用 GitHub API |
| `python3`（或 `python`） | 全部 | JSON 解析、脚本调用 |
| `docker` | issue-3 的 `build` | 镜像构建（Mac 可用 Docker Desktop） |
| `kubectl` | issue-2 真预览 / issue-3 的 `verify` | K8s 预览部署校验 |
| `node` ≥ 20 | umbrella 业务仓库有前端时 | vite 6 依赖 `crypto.hash`（Node 20.12+），node18 会编译 500 |

### 凭据准备

创建两个凭据文件（放哪都行，**别提交、别回显**）：

**`github.txt`**（必需）：
```text
github_token: ghp_你的GitHubToken
```

**`jenkins.txt`**（仅真 k8s 预览需要）：
```text
https://jenkins.osinfra.cn/
username: 你的jenkins用户名
password: 你的jenkins密码或API token
```

### 创建调试 Issue

在 [backlog 仓库](https://github.com/opensourceways/backlog/issues) 建一个 **[任务] Issue**（标题随意，如"test-local-debug"），记下编号。后面的命令里所有 `<issue号>` 都换成这个编号。

---

## 使用方法

### 需求分析（issue-1）：直接调脚本

没有专用调试器，但脚本独立可跑，不需要 local-debug 的任何 setup：

```bash
cd /你的/本地/backlog/仓库

# 默认 dry-run（出产物到本地，不 push）
bash .ai-flow/scripts/analyze_requirement.sh --issue-number 916

# 产物确认无误 → 发布（push 分支 + 开 PR 到 backlog）
bash .ai-flow/scripts/analyze_requirement.sh --issue-number 916 --publish
```

前提：`GH_TOKEN` 已设、`claude` 或 `opencode` 已装。脚本会自动拉 spec 仓模板和 agent 角色提示词，调 AI 产出需求分析说明书。

**如何与线上衔接**：`--publish` 会 push 分支并开 PR 到 backlog 仓库。PR 合入后，bot 打 `accepted` 标签 → 自动触发线上 issue-2 开发预览，实现本地 dry-run → 确认发布 → 线上自动接续的完整闭环。

---

### issue-2 调试器：修改 orchestrate.sh / gates 后用

**典型场景**：改动了 `orchestrate.sh` 或 gates 脚本，想在 push 前验证。

**第一步：进入你的 backlog 仓库**（包含你所有本地改动的那个）：

```bash
cd /你的/本地/backlog/仓库
```

**第二步：setup（只需一次）**

```bash
git pull   # 保持本地 backlog 最新

# 只看 AI 改代码效果（任何机器都行）
bash docs/local-debug/local-debug.sh setup 850 \
  --umbrella om-datacenter \
  --engine opencode \
  --gh-token-file ~/creds/github.txt

# 如果要真 k8s 预览部署（必须在 Linux 白名单机器跑）
bash docs/local-debug/local-debug.sh setup 850 \
  --umbrella om-datacenter \
  --engine opencode \
  --gh-token-file ~/creds/github.txt \
  --jenkins-file ~/creds/jenkins.txt \
  --real-preview
```

setup 做了什么：
1. 用 GitHub API 拉 issue #850 的标题+正文+评论 → `~/issue2-debug/ai/issue.txt`
2. clone 业务仓库（umbrella）→ `~/issue2-debug/om-datacenter`
3. clone agent 提示词仓库（spec）→ `~/issue2-debug/.spec`
4. 如果开了 `--real-preview` + `--jenkins-file`，自动申请临时 kubeconfig
5. 把配置写入 `~/issue2-debug/.ldconfig`

**第三步：分阶段跑（零参数，零 export）**

```bash
bash docs/local-debug/local-debug.sh design    # 只出设计文档
bash docs/local-debug/local-debug.sh dev        # 设计冻结 → AI 改代码 → 部署 → 冒烟
bash docs/local-debug/local-debug.sh deploy     # 只重部署（代码不动）
bash docs/local-debug/local-debug.sh run        # 完整一条龙：design → dev → deploy
bash docs/local-debug/local-debug.sh submit     # 门禁检查 + review + tester + 开 PR
```

**第四步：验证产物**

| 跑完哪个 | 看什么 | 路径/命令 |
|---------|--------|----------|
| `design` | 设计文档 | `cat ~/issue2-debug/ai/design.md` |
| `dev` | 代码改动 | `git -C ~/issue2-debug/om-datacenter diff` |
| `run` | 预览 URL | 终端输出 / 调试 issue 的 bot 回评 |
| `submit` | 门禁结果 + PR | 检查 issue 评论中 bot 是否开了 PR |

**第五步：确认无误后推送到远端**

```bash
cd /你的/本地/backlog/仓库
git diff                          # 再看一眼你的改动
git add .ai-flow/src/ scripts/ services/
git commit -m "fix: 说明你的改动"
git push origin main
```

推完后，线上 CI 下一次触发就会用到你改的新脚本。

**关于 commit 身份**：`dev`/`submit` 会自动 `git commit` + `push`，本地默认走兜底身份 `opensourceways-bot`。要挂你自己的名字，在跑 `dev` 前 export：

```bash
export COMMITTER_NAME="你的github用户名"
export COMMITTER_EMAIL="你的github邮箱"
bash docs/local-debug/local-debug.sh dev
```

> 线上 CI 会通过 `resolve_committer.py` 从 `user-info.yaml` 匹配评论者身份，本地没有这套机制，所以需要手动 export。

| 命令 | 对应 orchestrate mode | 线上等价触发 |
|------|----------------------|-------------|
| `design` | `FORCE_UPDATE_DESIGN=true` | `/ai-develop-preview --design` |
| `dev` | `SKIP_DESIGN=true` | `/ai-develop-preview --skip-design` |
| `deploy` | `DEPLOY_ONLY=true` | `/ai-develop-preview --deploy-only` |
| `run` | 完整 preview | `/ai-develop-preview` |
| `submit` | `PHASE=submit` | `/ai-develop-submit` |

---

### issue-3 调试器：修改服务配置后用

**典型场景**：新增或修改了 `services/<服务>.yaml`，或改了 `apply_tag_sync.py`，想确认 tag 能否正确命中 GitOps 仓库。

**一条命令完成确定性校验**：

```bash
cd /你的/本地/backlog/仓库
bash docs/local-debug/local-debug-issue-3.sh 785
```

自动完成：
1. 从 `GH_TOKEN` 环境变量 → 当前目录 → 仓根 → 家目录，自动找 `github.txt`
2. 从 issue #785 的标签自动解析 `project:<svc>` 路由到服务
3. 跑 `resolve_service.py` 解析 `services/<svc>.yaml` 的 `release.tag_sync` / `argocd` 配置
4. 枚举构建单元（单仓得 `.|<repo>|<repo>`，多仓从 `.gitmodules` 推导）
5. 跑 `apply_tag_sync.py` **dry-run**（只读远端 GitOps 仓库文件，在内存里算 tag 命中数，不 clone、不 commit、不 push）

**进阶**（需 docker/kubeconfig）：

```bash
bash docs/local-debug/local-debug-issue-3.sh setup 785 \
  --labels project:om-datacenter --gh-token-file ~/creds/github.txt

bash docs/local-debug/local-debug-issue-3.sh resolve   # 看 release 配置
bash docs/local-debug/local-debug-issue-3.sh build     # docker build（不 push，tag=:dryrun）
bash docs/local-debug/local-debug-issue-3.sh tagsync   # tag dry-run
bash docs/local-debug/local-debug-issue-3.sh verify    # kubectl 只读校验 ArgoCD 现网

bash docs/local-debug/local-debug-issue-3.sh clean     # 清掉 ~/issue3-debug
```

**推送到远端生效**：确认无误后，把你改的 `services/*.yaml` 或脚本 `git push` 到 backlog main。

> 真推镜像 / 改 GitOps / 开 PR / pre-release 请在远端对调试 issue 评论 `/ai-deploy-test`，调试器只管本地校验。

---

### test 调试器：架构设计完成后生成测试用例

**典型场景**：issue #818 的架构设计文档已合入 main，想在本地用 AI 先跑一遍测试策略，看质量合不合格，再决定要不要在远端正式触发。

**一条命令生成**：

```bash
cd /你的/本地/backlog/仓库
bash docs/local-debug/local-debug-test.sh 818
```

自动过程：
1. 找 `github.txt`，拉 spec 仓的测试模板 + agent 角色提示词
2. clone `integration-tests`（用例 skills + 融合目标仓）
3. 拉 issue #818 的架构设计文档 → `~/test-debug/ws/arch/`
4. 自动选 AI 引擎（装了 `claude` 用 claude，否则用 opencode）
5. 跑 `architecture-to-test.yml` 同一个 agent + template

**产出**：
- `~/test-debug/ws/Test/test-design-report.md` — 测试策略设计说明书
- `~/test-debug/ws/Test/test_design_cases.py` — pytest 测试用例脚本

**融合到集成测试集**（可选）：

```bash
bash docs/local-debug/local-debug-test.sh aggregate
git -C ~/test-debug/ws/integration-tests diff --stat    # 只看 diff，不 push
```

---

## 全新环境搭建指南

> **终端选择说明**：Windows 用户需要用**两个不同的终端**——安装工具用 PowerShell（`winget`、`npm`），运行 local-debug 用 Git Bash（`bash` 脚本）。装 git 后右键桌面就有 "Git Bash Here"。Linux/Mac 用户全程用一个终端即可。

### Windows 环境

**1. 安装必要工具（在 PowerShell 中运行）**

```powershell
# Git（同时会安装 Git Bash，local-debug 的 bash 脚本全靠它）
winget install Git.Git
# 或从 https://git-scm.com/download/win 下载安装

# Python 3
winget install Python.Python.3.12

# Claude Code（推荐，Node 自带）
winget install OpenJS.NodeJS.LTS     # 装 Node.js >= 20
npm install -g @anthropic-ai/claude-code
```

**2. 克隆 backlog 仓库（打开 Git Bash，以下全部在 Git Bash 中运行）**

```bash
git clone https://github.com/opensourceways/backlog.git
cd backlog
```

**3. 准备凭据**

在任意目录创建 `github.txt`：
```text
github_token: ghp_你的token
```

**4. 创建调试 issue**

浏览器打开 https://github.com/opensourceways/backlog/issues ，新建一个 Issue，记下编号。

**5. 开工（Git Bash）**

```bash
bash docs/local-debug/local-debug.sh setup <你的issue号> --umbrella om-datacenter --gh-token-file C:/Users/你的用户名/creds/github.txt --engine claude
bash docs/local-debug/local-debug.sh design
```

> Windows 注意：路径用正斜杠 `/`（Git Bash 兼容），不要用反斜杠 `\`。

> Windows 本机可跑 design/dev、issue-3 的 resolve/tagsync。真 k8s 预览部署请切 Linux 白名单机器。

### Linux 环境

> 以下所有命令都在同一个终端中运行，无需切换。

**1. 安装必要工具**

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y git curl python3 python3-pip

# Claude Code / OpenCode（二选一）
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
npm install -g @anthropic-ai/claude-code
# 或者
npm install -g @anthropic-ai/opencode

# 如果要真 k8s 预览
sudo snap install kubectl --classic
# docker 一般已预装
```

**2. 克隆 backlog**

```bash
git clone https://github.com/opensourceways/backlog.git
cd backlog
```

**3. 准备凭据**

```bash
mkdir -p ~/creds

# github.txt（必需）
cat > ~/creds/github.txt <<'EOF'
github_token: ghp_你的token
EOF

# jenkins.txt（可选，仅真预览需要）
cat > ~/creds/jenkins.txt <<'EOF'
https://jenkins.osinfra.cn/
username: 你的用户名
password: 你的密码
EOF

# 权限收紧
chmod 600 ~/creds/*.txt
```

**4. 创建调试 issue**

浏览器打开 https://github.com/opensourceways/backlog/issues ，新建一个 Issue，记下编号。

**5. 开工**

```bash
# 只看 AI 效果
bash docs/local-debug/local-debug.sh setup <issue号> --umbrella om-datacenter --gh-token-file ~/creds/github.txt --engine claude

# 要真 k8s 预览（白名单机器才有效）
bash docs/local-debug/local-debug.sh setup <issue号> --umbrella om-datacenter \
  --gh-token-file ~/creds/github.txt --jenkins-file ~/creds/jenkins.txt --real-preview --engine claude

bash docs/local-debug/local-debug.sh design
```

---

## 核心设计原则

### 薄包装 · 零漂移

```
local-debug.sh --(准备环境)--> 真 orchestrate.sh
     ↑                              ↑
 只处理 clone/token/目录        你本地改的直接生效
                                推送到远端 → CI 也跑同一份（全新 clone 同分支）
```

- 调试器**不复刻**任何 logic，只 `env ... bash $TOOLS_DIR/.ai-flow/src/orchestrate.sh`
- `TOOLS_DIR` 就是本地这份 backlog 仓——改了什么脚本，调试器直接测到改动
- jenkins 申请 kubeconfig 也复用 spec 仓里 issue-2 同一个脚本
- 角色提示词来自 setup clone 的 spec 仓（与线上同源）
- **push 到远端后，GitHub Actions `rm -rf` + 全新 clone，拉到你刚推的脚本，本地验证通过 = 远端大概率通过**

### 工作目录隔离（铁规）

所有产物只落独立目录，绝不碰 GitHub Actions runner 的工作目录、绝不写 `/tmp`：

| 调试器 | 默认工作目录（Mac/Linux） | 默认工作目录（Windows） |
|--------|-------------------------|------------------------|
| issue-2 | `~/issue2-debug/` | `C:/issue2-debug/` |
| issue-3 | `~/issue3-debug/` | `C:/issue3-debug/` |
| test | `~/test-debug/` | `C:/test-debug/` |

可用 `--root` 自定义。

### 安全红线

- 凭据只读进内存临时用，**绝不回显 / 提交**
- `.ldconfig` / `.ld3config` / `.ldtconfig` 只存**文件路径**，不存明文
- clone 输出已 `***@github` 脱敏
- **真跑会 push/评论/开 PR/真部署** → 必须用专门的调试 issue

---

## 你需要知道的关键概念

### issue.txt 是什么

`setup` 时从 GitHub 拉取的 issue 内容快照（标题+正文+全部评论），存在工作目录里。跑 design/dev 时，AI agent 把它拼进 prompt 作为任务上下文。**只在 setup 时刷新**，不会自动同步线上升级。要拿最新评论，重新跑一次 `setup`。

### 分支名怎么来的

`orchestrate.sh` 自动计算：`issue-{编号}-from-{仓库默认分支名}`。例如 `issue-785-from-main`。**本地和线上用同一个分支名**——本地 `submit` 推到这个分支，线上 CI 全新 clone 时拉同一个分支，实现无缝衔接。

### 哪些改动需要手动 push

| 改的文件在哪 | 怎么生效 |
|------------|---------|
| `backlog` 仓库里的脚本（`orchestrate.sh` / gates / scripts / services） | 手动 `git push` |
| umbrella 业务仓的代码 | `submit` 自动 push + 开 PR |

### tag 命中是什么意思

`apply_tag_sync.py` 在 GitOps 仓库的 values.yaml 里找你的镜像对应的 key，找到并把 tag 从旧版本改成新版本 = 命中。这一步是发布链路的入口——命中了，ArgoCD 才能自动同步到集群。`tagsync` 命令是 dry-run：只读远端文件在内存里模拟，不真写。

### GitOps 仓库和 ArgoCD

- **GitOps 仓库**（如 `infra-common`）：存放声明式 YAML 文件，描述"集群应该长什么样"。和管代码没本质区别——只是文件内容是 K8s 配置而非源代码
- **ArgoCD**：跑在集群里的控制器，监控 GitOps 仓库的 YAML 文件。发现文件变了 → 让集群实际状态对齐。Git 里写什么，集群就长什么样（IaC 的 K8s 实现）

---

## 关键文件索引

| 文件 | 说明 |
|------|------|
| `docs/local-debug/LOCAL-DEBUG.md` | issue-2 调试手把手文档（146 行） |
| `docs/local-debug/local-debug.sh` | issue-2 调试器脚本（203 行） |
| `docs/local-debug/LOCAL-DEBUG-issue-3.md` | issue-3 调试手把手文档（33 行） |
| `docs/local-debug/local-debug-issue-3.sh` | issue-3 调试器脚本（278 行） |
| `docs/local-debug/LOCAL-DEBUG-test.md` | test 调试手把手文档（34 行） |
| `docs/local-debug/local-debug-test.sh` | test 调试器脚本（231 行） |

---

## 🔗 相关笔记

- [[backlog-architecture]] — 本地调试直调 orchestrate.sh
- [[ai-flow如何串联全组织]] — ai-flow 全景
- [[术语解释]] — Agent 角色等术语

> 索引：[[ai-flow 体系]] · 返回 [[首页]]
