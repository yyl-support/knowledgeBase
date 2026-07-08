# pipelineascode 四工程关系总览

## 基础设施：真实集群拓扑

### 测试环境

```
Karmada 控制面: 1.95.134.239:5443

├── 成员集群 006
│       IP: 1.95.209.90:5443
│       类型: CPU + 少量 NPU
│
├── 成员集群 007 ( openmerlin-guiyang )
│       IP: 1.95.6.19:5443
│       类型: CPU 计算
│
└── Karmada Proxy
        URL: http://1.95.134.239:5443/apis/search.karmada.io/
             v1alpha1/proxying/karmada/proxy
```

### 生产环境

```
Karmada 控制面: 1.95.223.182:5443 ( 贵阳 )

├── 成员集群 0001
│       IP: 101.245.109.198:5443
│       类型: 通用 CPU 计算
│
├── 成员集群 wlcb ( 乌兰察布 )
│       IP: 1.92.221.43:5443
│       类型: Ascend 910B NPU 集群
│
└── 成员集群 guiyang
        外网: 1.95.170.83:5443
        内网: 10.0.1.27:5443 ( IPv6 )
        类型: 通用计算
```

### 关键区分

| 项目 | 测试环境 | 生产环境 |
|---|---|---|
| Karmada 控制面 | 1.95.134.239 | 1.95.223.182 |
| NPU 集群 | 无独立 NPU 集群 | wlcb ( 1.92.221.43 ) |
| 容器镜像仓库 | harbor-portal.osinfra.cn | swr.cn-north-4.myhuaweicloud.com |
| 命名空间路由 | argo (默认) | argo / ragsdk / op-plugin 等按仓库分流 |
| Git 缓存 | gitcode-cache.osinfra.cn | 同，内网 DNS 解析 |

---

## 工程清单

| 工程 | 语言 | 角色 | 源码 |
|---|---|---|---|
| **codearts-workflow-image** | Go | CI/CD 流水线执行引擎 ( 核心 ) | pipelineascode/codearts-workflow-image |
| **git-cache-http-server** | Haxe/Node.js | Git 缓存代理 | pipelineascode/git-cache-http-server |
| **image_preheat** | Python/Bash | 容器镜像预热 | pipelineascode/image_preheat |
| **cronjob** | Python | Karmada 集群运维 | pipelineascode/cronjob |

---

## 一、各自定位

### 1. codearts-workflow-image — 核心引擎

将用户 CI/CD 脚本 ( **`shell.sh` + `env.sh`** ) 自动转换为 **Volcano Job CRD**，提交到 Karmada 多集群联邦执行。

**核心能力：**

- 解析 `CP_runs_on` 规格 ( arch-cpu-mem-chip-npu )
- 自动计算资源 ( CPU / 内存 / NPU )，匹配 Ascend 芯片 ( 910A / B1-B4 / 310P3 )
- 生成 Git 克隆脚本 ( 带 CDN 缓存代理 )
- 生成产物复制脚本 + Sidecar 容器
- 处理敏感环境变量 → K8s Secret
- 提交到 Karmada 并流式跟踪日志
- 多集群调度 ( 基于 NPU / PVC 的 Karmada dispatch label )

**输入 → 输出：**

```
shell.sh + env.sh + workflow_templatev2.yaml
    → convert_to_yaml
    → workflow.yaml ( Volcano Job CRD ) + workflow-secret.yaml
    → submit
    → Volcano Job 在 Karmada 集群上运行
```

### 2. git-cache-http-server — Git 缓存代理

透明 Git 镜像缓存 HTTP 服务。CI/CD Runner 请求 Git 仓库时，请求被路由到缓存而非上游，减少公网带宽。

**核心能力：** 拦截 git clone / fetch，本地维护 mirror 副本；首次 clone 后仅 fetch 增量。

### 3. image_preheat — 镜像预热

Harbor Webhook 驱动的镜像预热服务。镜像 push 到 Harbor 后立即在所有 Karmada 集群节点上预拉取。

**核心能力：** 接收 Harbor `PUSH_ARTIFACT` webhook；通过 Karmada Proxy API 穿透到每个 member 集群创建预热 Pod；架构感知 ( -amd64 / -arm64 / multi-arch )。

### 4. cronjob — Karmada 集群运维

| 脚本 | 功能 |
|---|---|
| `force-patch-stuck-rb/patch.py` | 强制调度卡在 SchedulerError 的 ResourceBinding |
| `vcjob-ttl-cleaner/clean.py` | 清理终端状态的 Volcano Job |

---

## 二、四者如何在真实集群上协作

### 协作全景

```
CodeArts Pipeline 引擎
│  Stage 1 (编译) → Stage 2 (测试) → Stage 3 (训练) → Stage 4 (打包)
│  每个 Stage 调用 converter + submit
│
▼
git-cache-http-server
│  部署在 Karmada 集群内 ( ClusterIP Service )
│  git config url."...cache.osinfra.cn".insteadOf ...
│  → Runner clone 走内网缓存，不走公网
│
▼
codearts-workflow-image
│
│  1. converter 生成 Volcano Job
│  2. submit 提交到 Karmada 控制面
│     ( 测试 1.95.134.239 / 生产 1.95.223.182 )
│  3. dispatch label 自动路由:
│     • CP_runs_on 含 NPU → dispatch/wlcb=true ( 发到 1.92.221.43 )
│     • CP_dataset 含 PVC → pvccluster 查 PVC 所在集群后打标
│     • 纯 CPU 无 PVC → 按默认 PropagationPolicy 分发
│  4. Karmada 根据 label + policy 分发到目标 member 集群
│
├─────────────────────────────────────┐
│                                     │
▼                                     ▼
image_preheat                       cronjob
│                                     │
│  Harbor push 镜像                   │  • patch.py: 修复卡在
│  → webhook 触发                     │    SchedulerError 的
│  → 通过 Karmada Proxy 对所有        │    ResourceBinding
│    member 集群的 Node 预拉取镜像     │  • clean.py: TTL 后删除
│                                     │    终端 VCJob，输出 wlcb
│                                     │    集群 NPU 资源摘要
│                                     │
└──────────────┬──────────────────────┘
               │
               ▼
Karmada 多集群联邦
│
├── 测试环境 ( 控制面: 1.95.134.239 )
│     ├── 006: 1.95.209.90
│     └── 007: 1.95.6.19
│
└── 生产环境 ( 控制面: 1.95.223.182, 贵阳 )
      ├── 0001: 101.245.109.198 ( CPU )
      ├── wlcb: 1.92.221.43 ( Ascend NPU )
      └── guiyang: 1.95.170.83 (外) / 10.0.1.27 (内, IPv6)
```

---

## 三、调度决策机制

### 一个 Stage 的完整路由链路

以 Stage 3 ( 模型训练，`CP_runs_on=arm64-cpu-12-mem-48G-910b4-2` ) 为例：

```
1. env.sh 被 source 后:
   CP_runs_on="arm64-cpu-12-mem-48G-910b4-2"  ← 需要 2 颗 910B4

2. converter 解析:
   → 芯片 = 910b4 → ascend-1980 资源类型
   → 2 颗 → 请求 24 CPU + 96Gi 内存 + 2 ascend-1980

3. submit 查找目标集群:
   → 遍历所有 member 集群 ( 0001, wlcb, guiyang )
   → wlcb ( 1.92.221.43 ) 有 ascend-1980 资源
   → 打标: dispatch/wlcb=true

4. Karmada 收到:
   → 标签指向 wlcb → 通过 ResourceBinding 绑定到 wlcb
   → wlcb 的 Volcano Scheduler 找有 2 颗空闲 NPU 的节点
   → 创建 Pod → 拉起容器 → 执行 shell.sh
```

### PVC 和 NPU 同时存在时

**场景 A — 两者指向同一集群：**

```
CP_runs_on = "arm64-cpu-12-mem-48G-910b4-2"    ← 必须去 wlcb
CP_dataset = "/dataset/model-weights,readonly"  ← PVC 也在 wlcb

→ 打标 dispatch/wlcb=true → 正确路由 ✓
```

**场景 B — PVC 决定目的地，CP_runs_on 不限定：**

```
CP_runs_on = "amd64-cpu-8-mem-16G"             ← 哪都行
CP_dataset = "/dataset/model-weights,readonly"  ← PVC 在 wlcb

→ pvccluster 检测到 PVC 在 wlcb → 打 dispatch/wlcb=true
→ 虽然是纯 CPU，但因为数据在 wlcb，也必须去 wlcb 跑
```

---

## 四、完整时序

```
 1. 开发者 push 代码到 gitcode.com
 2. 开发者 push 镜像到 Harbor ( swr.cn-north-4... )
    │
 3. Harbor → Webhook → image_preheat
    → 在 wlcb ( 1.92.221.43:5443 ) 的 NPU 节点上预拉取新镜像
    → 通过 Karmada Proxy ( 1.95.223.182:5443/apis/.../proxy ) 穿透
    │
 4. CodeArts 触发 Pipeline
    │
 5. Stage 准备 → git clone
    → git config url.insteadOf 生效
    → 请求走 git-cache-http-server ( 内网 )
    → 缓存 fetch 增量后响应
    │
 6. converter 吃 env.sh + shell.sh → 产出 Volcano Job YAML
    │
 7. submit 检查:
    → CP_runs_on=910b4 → wlcb 有 NPU → dispatch/wlcb=true
    → 打标，提交到 Karmada 控制面 ( 1.95.223.182 )
    │
 8. Karmada Scheduler → ResourceBinding → wlcb 集群
    │
 9. wlcb 的 Volcano Scheduler → 分配有 2 颗空闲 910B4 的节点
    │
10. Pod 启动 → 镜像已在本地 ( 第 3 步预热 ) → 秒级启动
    │
11. 容器执行 shell.sh → torchrun 多卡训练
    │
12. 训练完成 → 产物写入 /output → Sidecar 看守
    │
13. submit kubectl cp 拉走产物 → Job 完成
    │
14. [定期] cronjob/clean.py 扫描 → TTL 后 DELETE 终端 Job
```

---

## 五、kubeconfig 配置说明

| 文件 | 用途 | 关键点 |
|---|---|---|
| `测试/karmada.yaml` | 测试 Karmada API | 1.95.134.239:5443，管理员证书 |
| `测试/karmada-proxy.config` | 测试 Karmada Proxy | 同 IP，路径追加 /apis/search.karmada.io/ v1alpha1/proxying/karmada/proxy |
| `测试/006.yaml` | 测试成员集群 | 1.95.209.90:5443 |
| `测试/007` | 测试成员集群 | 1.95.6.19:5443 ( openmerlin-guiyang ) |
| `正式/正式贵阳karmada.yaml` | 生产 Karmada API | 1.95.223.182:5443 |
| `正式/0001.yaml` | 生产成员集群 | 101.245.109.198:5443 |
| `正式/wlcb.yaml` | 生产 NPU 集群 | 1.92.221.43:5443 ( 乌兰察布 Ascend ) |
| `正式/guiyang-ipv6.yaml` | 生产贵阳集群 | 外 1.95.170.83 / 内 10.0.1.27 |

---

## 六、关键设计要点

1. **一个 Stage = 一个 Volcano Job = 一个 CP_runs_on**
   多 Stage Pipeline 靠 CodeArts 引擎分阶段调用 converter+submit，每个 Stage 独立负责自己的 env.sh

2. **NPU 和 PVC 统一用 dispatch label 路由**
   它们虽然分属算力和存储两个领域，但共享同一个"Job 必须去哪"的问题

3. **karmada-proxy.config 的路径区别于 karmada.yaml**
   前者在 server URL 末尾追加了 Karmada cluster proxy 路径，用于 image_preheat 穿透到 member 集群

4. **测试和生产用不同 Karmada 控制面**
   1.95.134.239 ( 测试 ) vs 1.95.223.182 ( 生产 )，证书不相同

5. **生产唯一 NPU 集群是 wlcb**
   所有需要 Ascend 910B 的训练/推理任务最终都路由到 1.92.221.43
