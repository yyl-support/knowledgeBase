## Volcano Job CRD

### 通俗理解

把 Volcano Job 想像成一张**外卖订单**：

- 你写 `shell.sh` = 你想吃什么菜（要执行的脚本）
- 你写 `env.sh` = 口味偏好（环境变量，如 NPU 几颗、内存多大）
- **Volcano Job** = 印出来的那张小票，上面写清楚了"几号桌、什么菜、谁来做"
- Volcano 调度器 = 后厨，拿小票分配厨师和灶台

你不用管后厨怎么忙、有几个厨师，你只需要关心小票上的内容对不对。

### 在 pipelineascode 里你怎么用它

你根本不需要手写 Volcano Job 的 YAML。你只需要写两个文件：

**env.sh**（告诉系统你要什么资源）：
```bash
export CP_runs_on="arm64-cpu-16-mem-32G-910b4-2"   # 2颗昇腾910B4，16核，32G内存
export CP_docker_image="swr.cn-north-4.myhuaweicloud.com/myteam/myimage:v1"
export CP_dataset="/dataset/model-weights,readonly"  # 挂载模型权重，只读
```

**shell.sh**（告诉系统你要执行什么）：
```bash
python train.py --epochs 100 --batch-size 64
```

然后 `codearts-workflow-image` 的 converter 自动把你的两个文件"翻译"成一个 Volcano Job YAML，submit 负责提交到集群。你全程不需要碰 K8s YAML。

### 和 K8s 原生 Job 的区别

K8s 原生的 Job 就像单灶台——适合跑一个简单的后台任务。Volcano Job 则是专业后厨——支持：

- **多角色并行**：训练 + 推理可以写在一个 Job 里
- **排队**：资源不够时自动排队，不会直接失败
- **NPU 感知**：知道哪里有昇腾卡，把你的训练任务分过去
- **失败自动停**：一个 Pod 挂了立刻中止整个 Job，不浪费资源

---

## 多集群联邦执行

### 通俗理解

假设公司有三个机房：
- 机房 A 全是昇腾 NPU 机器（跑 AI 训练）
- 机房 B 全是普通 CPU 机器（跑编译打包）
- 机房 C 有特殊的数据集存储（跑数据处理）

**多集群联邦 = 一个总控台**。你把任务丢给总控台，说"我这个需要 NPU"，总控台自动帮你发到机房 A，你完全不需要知道机房 A 在哪、IP 是多少。

### 在 pipelineascode 里你怎么用它

你同样不需要操心。你只需要在 `env.sh` 里写清楚资源需求：

```bash
# 要 NPU → 自动发到有 Ascend 芯片的集群
export CP_runs_on="arm64-cpu-12-mem-48G-910b4-1"

# 不要 NPU → 自动发到通用 CPU 集群
export CP_runs_on="amd64-cpu-8-mem-16G"
```

系统做了三件事：
1. **kubeconfig 选择器**扫描所有集群，找到有可用 NPU 的那个
2. **dispatch label** 自动打标，告诉 Karmada"往这个集群发"
3. **PropagationPolicy** 按规则分发（比如 ragsdk 命名空间的任务固定发到 member2）

## PVC（PersistentVolumeClaim）

### 通俗理解

把 PVC 想像成 **Kubernetes 里的"U 盘申请单"**：

- PV = 真实的 U 盘（物理存储，谁家的 NAS、多大容量），插在机房某个柜子里
- PVC = 你填的一张小纸条，写上"我要一个 100G 的 U 盘"
- K8s 拿到纸条，自动去柜子里找个 100G 的 U 盘，插到你的 Pod 上
- 容器里 `/dataset` 目录就直接能读写这个 U 盘了

你不需要知道 U 盘是哪个牌子、插在哪个柜子——那些是 PV 的事。你只填 PVC 就行了。

### 在 pipelineascode 里你怎么用它

**场景：跑模型训练需要加载 50G 的预训练权重**

不用 PVC 的做法：
```bash
# shell.sh 里写——每次跑都要重新下载，慢且费流量
wget https://xxx/model-weights.bin  # 每次等 10 分钟
python train.py
```

用 PVC 的做法——**只需要一行配置**：
```bash
# env.sh 里写
export CP_dataset="/dataset/model-weights,readonly"
```

converter 自动帮你：
1. 在 Volcano Job YAML 里加上对应的 PVC 卷声明
2. 把 PVC 挂载到容器的 `/dataset/model-weights`
3. 给 Job 打上 `dispatch/<集群名>=true` 标签，确保发到数据所在的那个集群（因为 PVC 只存在于特定集群）

容器启动后 `/dataset/model-weights` 下直接就是那 50G 的权重文件，零等待。

### 几种用法

| CP_dataset 值                | 容器里看到的效果                   |
| --------------------------- | -------------------------- |
| `/dataset/weights`          | 读写模式挂载到 `/dataset/weights` |
| `/dataset/weights,readonly` | 只读模式挂载（推荐，防止误删）            |
| 不设置                         | 没有 PVC，纯靠镜像或 wget          |

### 和 EmptyDir 的区别

- **PVC**：数据在集群外面（NAS/Ceph），不同 Pod 可以共享，Pod 重启数据还在
- **EmptyDir**：数据在节点本地磁盘上，Pod 删了数据就没了。`CP_artifacts` 产出的构建结果就用 EmptyDir，因为只需要临时存放等着 `kubectl cp` 拉走

---

## ResourceBinding

### 通俗理解

Karmada 收到你的 Volcano Job 后，不会直接把它发出去。而是先写一张**派工单**，上面写着"这个 Job，发到 member2 集群去"——这张派工单就是 ResourceBinding。

派工单没写好 → 不发货；派工单写好了 → 各集群的 Karmada Agent 读到后去执行。

### 在 pipelineascode 里它怎么影响你

正常情况下你感知不到。但有两种异常：

1. **派工单卡住了**（`SchedulerError`）：Volcano Job 一直 Pending，永远不开始跑。`cronjob/patch.py` 的作用就是扫描所有卡住的派工单，强制补填目标集群
2. **派工单发错集群了**：比如 PVC 在 member1 但 Job 被发到了 member2 → Pod 起来后发现找不到数据卷。submit 组件通过 `pvccluster` 模块查询 PVC 位置后自动纠正

---

## PropagationPolicy

> `pp` = 此条目。同系列还有 `cpp` (集群级) 和 `cop` (覆写)，见下文。

### 通俗理解

类似快递分拣规则：
- 凡是寄到"argo 小区"的包裹（argo 命名空间）→ 全部转发到 member1 和 member2
- 凡是寄到"ragsdk 小区"的包裹 → 只转发到 member2
- 凡是 Volcano 类型的包裹 → 全部集群都配送一份

### 在 pipelineascode 里它怎么工作

`configs/propagation-policies/` 下有 10 个策略文件。你提交 Volcano Job 时不需要管这些——策略是预先配好的。但你的 `CP_runs_on` 和 `CP_dataset` 会通过 dispatch label 进一步细化"到底发到哪个集群"。

---

## Harbor Webhook

### Harbor 是什么

**Harbor** 是一个企业级的容器镜像仓库。可以理解为"公司内部的 Docker Hub"——你把 `docker build` 出来的镜像推到这里，别人 `docker pull` 从这里拉。

pipelineascode 用 Harbor 来存放所有 CI/CD 镜像（编译工具镜像、测试镜像、PyTorch 训练镜像等），地址类似：
```
swr.cn-north-4.myhuaweicloud.com/ai/pytorch-ascend:v2.1
```

### Webhook 是什么

**Webhook = 事件驱动的 HTTP 回调。** 别被名字唬住，本质就一件事：当某个事件发生时，Harbor 主动向你指定的 URL 发一个 HTTP POST 请求，把"刚才发生了什么"以 JSON 格式告诉你。

```
不是你去轮询 Harbor："有新镜像吗？有吗？有了吗？"
而是 Harbor 主动来敲门："嘿，有人 push 了个新镜像，这是详情。"
```

### 在 pipelineascode 里的完整流程

```
第 1 步：开发者 push 镜像
─────────────────────────────────────────────
  docker build -t pytorch-ascend:v2.2 .
  docker push swr.cn-north-4.myhuaweicloud.com/ai/pytorch-ascend:v2.2

  → 镜像存入 Harbor 仓库


第 2 步：Harbor 触发 Webhook
─────────────────────────────────────────────
  Harbor 检测到 PUSH_ARTIFACT 事件
  → 向 http://preheat-service:8080/webhook 发送 POST

  JSON 内容大概是：
  {
    "type": "PUSH_ARTIFACT",
    "event_data": {
      "repository": {
        "name": "pytorch-ascend",
        "namespace": "ai"
      },
      "resources": [{
        "tag": "v2.2",
        "digest": "sha256:abc123..."
      }]
    }
  }


第 3 步：image_preheat 收到通知
─────────────────────────────────────────────
  webhook_server.py：
  - 解析 JSON → 提取镜像全名
    swr.cn-north-4.myhuaweicloud.com/ai/pytorch-ascend:v2.2
  - 从 tag "v2.2" 中检测目标架构（amd64 / arm64 / multi）
  - 通过 Karmada Proxy 扫描所有成员集群的 Node


第 4 步：在所有匹配节点上预拉取
─────────────────────────────────────────────
  对于每个需要该镜像的节点：
  → 创建一个临时 Pod（command: ["true"]，啥也不干只启动）
  → 镜像拉取策略是 Always/IfNotPresent
  → kubelet 发现本地没有这个镜像 → 自动从 Harbor 拉取

  集群 A（wlcb, Ascend NPU 节点）
    → Node npu-01: 创建临时 Pod → 拉 v2.2
    → Node npu-02: 创建临时 Pod → 拉 v2.2

  集群 B（member2, CPU 节点）
    → Node cpu-01: 镜像 tag 不含 arm64 → 跳过
    → Node cpu-02: 同上，跳过


第 5 步：你的 Volcano Job 启动
─────────────────────────────────────────────
  几分钟后 Pipeline 触发 Stage 3（模型训练）：
  CP_docker_image = "swr.cn-north-4.../pytorch-ascend:v2.2"
  → Volcano Job 调度到 npu-01 节点
  → kubelet 发现 v2.2 已经在本地了
  → 秒级启动，不需要拉镜像
```

### 预热 vs 不预热

| | 不预热 | 有预热 |
|---|---|---|
| Pipeline 触发时 | Node 上没有镜像，现从 Harbor 拉 | Node 上已有镜像 |
| 镜像大小 5GB | 拉取 3-8 分钟 | 0 秒 |
| 超时风险 | 镜像还没拉完，Job 可能先超时 | 不存在 |
| 多个 Node 同时拉 | Harbor 带宽吃满 | 提前逐个预热，平稳 |

### 支持的架构检测逻辑

`image_preheat` 从镜像 tag 中自动判断该镜像的目标架构：

| Tag 示例 | 检测结果 | 行为 |
|---------|---------|------|
| `pytorch-ascend:v2.2-amd64` | 仅 AMD64 | 只在 AMD64 节点上预热 |
| `pytorch-ascend:v2.2-arm64` | 仅 ARM64 | 只在 ARM64 节点上预热 |
| `pytorch-ascend:v2.2` | Multi-arch | 所有架构的节点都预热 |

### 一句话

**Harbor Webhook = 仓库的"到货通知"；image_preheat = 提前把货分发到所有门店，保证顾客（Volcano Job）一到就能取货。** 没有这个机制，每次 Pipeline 跑 NPU 训练时都要先等 5 分钟拉镜像。

---

## CDN 缓存代理（Git 缓存代理）

### 通俗理解

你在公司内网，每次 `git clone` 一个 GitHub 上的大仓库都要走公网，又慢又费流量。

**Git 缓存代理**相当于公司内部悄悄存了一份 GitHub 仓库的"复印件"。你 clone 的时候实际上是从公司内部那台机器上拿，速度从几分钟变成几秒。

这套机制叫 CDN 缓存代理——**CDN** 原意是内容分发网络（把内容提前推到离用户最近的节点），在这里就是用本地镜像代理替代直接访问远端。

### 在 pipelineascode 里它是怎么工作的

每次 Volcano Job 启动，容器里跑的第一件事就是 git clone 代码。如果每次都要从公网拉，100 个 Pipeline 就拉 100 次，又慢又可能被限流。

converter 自动在脚本开头注入这段配置：

```bash
# 让 git 把对 gitcode.com 的请求"偷换"成对本地缓存服务器的请求
git config --global url."https://gitcode-cache.osinfra.cn/".insteadOf https://gitcode.com/
git config --global url."https://github-cache.osinfra.cn/".insteadOf  https://github.com/
```

效果：你写 `git clone https://gitcode.com/xxx/yyy.git`，但实际请求发到了公司内网的 `gitcode-cache.osinfra.cn` 这台服务器上。

### 缓存服务器本身怎么工作

`git-cache-http-server` 就是这个缓存服务器：
- 第一次有人 clone 某个仓库 → 它去公网拉一份 `--mirror` 存到本地
- 第二次有人 clone 同一个仓库 → 直接从本地 mirror 响应，不走公网
- 之后每次有请求，它先 `git fetch --prune --prune-tags` 同步最新代码，再响应

### 你不需要做任何事

converter 自动注入 CDN 配置，覆盖了 5 个 Git 提供商：

| 原始域名 | 缓存域名 |
|---------|---------|
| `gitcode.com` | `gitcode-cache.osinfra.cn` |
| `github.com` | `github-cache.osinfra.cn` |
| `gitee.com` | `gitee-cache.osinfra.cn` |
| `atomgit.com` | `atomgit-cache.osinfra.cn` |
| `codehub.devcloud.huaweicloud.com` | `codehub-cache.osinfra.cn` |

你正常写 `shell.sh`，不用管缓存的事——converter 帮你搞定了。

---

## CRD（Custom Resource Definition）

### 通俗理解

Kubernetes 出厂自带一些"标准资源"：Pod、Service、Deployment、ConfigMap……就像手机出厂自带电话、短信、相机。

但你想用 NPU 调度、批量任务队列、多集群分发——这些功能 K8s 原生不支持。就像你想在手机上装一个"昇腾 NPU 管理器"App——K8s 允许你自己定义新的资源类型，这就是 CRD。

**CRD = 你告诉 K8s："从今天起，除了 Pod 和 Service，我还认一种叫 Volcano Job 的东西。"**

定义完 CRD 后，你就可以写：

```yaml
apiVersion: batch.volcano.sh/v1alpha1   # ← 这个 API 路径不存在于原生 K8s
kind: Job                               # ← 这不是 K8s 原生的 Job，而是 Volcano 的 Job
spec:
  queue: shared-flexible-queue
  tasks: ...
```

`kubectl create -f volcano-job.yaml` 的时候 K8s 不再报"不认识这个类型"，而是把它存进 etcd、交给 Volcano Controller 去处理。

### 在 pipelineascode 里用到哪些 CRD

| CRD | API Group | 谁定义的 | 干什么 |
|-----|-----------|---------|--------|
| `Job` | `batch.volcano.sh/v1alpha1` | Volcano | 批量任务调度（converter 的输出就是它） |
| `ResourceBinding` | `work.karmada.io/v1alpha2` | Karmada | 记录工作负载分发到哪个成员集群 |
| `Cluster` | `cluster.karmada.io/v1alpha1` | Karmada | 描述一个成员集群的元信息 |
| `PropagationPolicy` | `policy.karmada.io/v1alpha1` | Karmada | 定义资源传播规则 |

### 一句话

**CRD 就是给 Kubernetes 装插件。** 你不装 Volcano 插件，K8s 就不知道什么是"带 NPU 的批量任务"；你不装 Karmada 插件，K8s 就不知道什么是"多集群分发"。pipelineascode 这套系统跑起来的前提，就是集群里已经装了 Volcano 和 Karmada 这两个 CRD 插件。

---

## Sidecar 容器

### 通俗理解

一辆**三轮摩托车**：司机在前面开车，旁边跨斗里坐着一个人干别的事——这就是 Sidecar。

一个 Pod 就像这辆摩托车，可以装多个容器。**主容器**跑你的 shell.sh，**Sidecar 容器**就在旁边干辅助活——两个人共享同一个网络、同一个文件系统，但各干各的。

```
Pod
├── main-script 容器
│   (你的 shell)
│   python train.py
│
├── copy-artifact 容器 (Sidecar)
│   等待主容器退出后
│   把 /output 里的文件搬走
│
└── 共享: /output (EmptyDir 卷)
```

### 在 pipelineascode 里怎么用它

当你在 env.sh 里写了 `CP_artifacts` 时，converter 会自动给 Volcano Job 加一个叫 **`copy-artifact`** 的 Sidecar 容器：

1. 你写 `CP_artifacts="build/*.so"` 和 `CP_artifacts_temp_folder="/output"`
2. converter 在 YAML 里加两个东西：
   - 一个 EmptyDir 卷（10Gi），挂载到 `/output`
   - 一个 Sidecar 容器，盯着一份 `.ascend-done` 标记文件
3. **主容器**跑你的脚本，结果写到 `/output/`
4. 主容器退出后，写一个 `.ascend-done` 文件
5. **Sidecar** 看到标记文件，知道"主容器的活干完了"，保持容器活着
6. submit 通过 `kubectl cp` 从 Sidecar 里把 `/output` 下的产物抽取出来

### 为什么不用主容器直接传

因为主容器退出后 Pod 就没了，来不及 `kubectl cp`。用 Sidecar 当"保险柜"——主容器挂了 Sidecar 还活着，你可以从容地把产物取出来再删 Pod。

### 和 initContainer 的区别

- **initContainer**：在主容器启动**之前**跑，跑完就退出。适合做初始化（比如下载依赖）
- **Sidecar**：和主容器**同时**跑，可以一直活到 Pod 结束。适合做持续辅助（日志采集、文件看守）

---

## Karmada Dispatch Label

### 通俗理解

假设你在一个三城市的配送中心下单。你的订单里有特殊要求——"必须用冷藏车"或者"必须从北京仓库发货"。

**Dispatch label 就是物流系统自动给订单贴的标签**：`发往:北京`。Karmada 看到标签后不做任何判断，直接按标签发——北京仓的订单去北京，上海仓的订单去上海。

### 为什么 NPU 和 PVC 用同一套机制

它们**共享同一个根本问题：资源不是到处都有**。

| 资源 | 属地性 |
|------|--------|
| Ascend 910B4 NPU | 只存在于特定几个集群（wlcb） |
| PVC "model-weights" | 只存在于某一个集群（member2） |
| PVC "test-dataset" | 只存在于另一个集群（member1） |

NPU 和 PVC 不是一个领域的东西——前者是算力、后者是存储。但在"这个 Job 能不能去某个集群"这件事上，逻辑完全一样：

```
submit 组件做的事（不区分 NPU 还是 PVC）：

1. 检查 Job 需要 ascend-1980 吗？
   → 查哪个集群有 → 打 dispatch/wlcb=true

2. 检查 Job 挂载了 PVC 吗？
   → pvccluster 模块查出 PVC 在 member2
   → 打 dispatch/member2=true

3. 都没特殊需求？
   → 不打标，走默认 PropagationPolicy 扩散到全部集群
```

### 实际例子

```yaml
# 一个同时要 NPU 和数据集 PVC 的 Job，submit 自动打好：
kind: Job
metadata:
  labels:
    dispatch/wlcb: "true"       # ← NPU 在 wlcb 集群
    dispatch/member2: "true"    # ← PVC "model-weights" 在 member2 集群
```

Karmada 收到后只做一件事：标签说去 wlcb 就去 wlcb，标签说去 member2 就去 member2。如果两个标签指向不同集群，就都发。

### 一句话

**NPU 决定 Job 该去哪（算力在哪），PVC 也决定 Job 该去哪（数据在哪）。** 路径不同、问题相同、解决方法相同——所以用同一套 dispatch label，而不是两套独立机制。

---

## CI/CD Runner

### 通俗理解

CI/CD 平台（CodeArts、Jenkins、GitLab CI）是"工头"，负责接收任务、排顺序、记录结果。但工头自己不动手干活——他手下有**一群工人**，工人叫 Runner。

```
你 push 代码
  → CodeArts 收到："好，有个 Pipeline 要跑"
  → 翻看标签："Stage 1 需要 amd64，Stage 3 需要 NPU"
  → 找 Runner：
       Runner A（普通 CPU 机器）说："我能跑 Stage 1、2、4"
       Runner B（Ascend NPU 机器）说："我能跑 Stage 3"
  → 工头把 Stage 1 派给 Runner A，Stage 3 派给 Runner B
```

### 在 pipelineascode 里 Runner 是什么

pipelineascode 没有传统的常驻 Runner 进程。它的"Runner"就是 **Volcano Job 里跑起来的那个 Pod**。

传统模式：
```
Runner 是一台常驻机器，装好各种工具，来一个任务在本地跑一个
→ 问题是：要 NPU 的时候这台机器没有，就得另配一台 Runner
```

pipelineascode 模式：
```
没有常驻 Runner。每个 Stage 触发后 → converter 生成 Volcano Job → 
Karmada 把它丢到有对应资源的集群 → Pod 启动 → 容器跑你的 shell.sh → 跑完就销毁
→ "Runner"是动态创建的、按需分配的、用完就扔的
```

### 两种 Runner 模式对比

| | 传统 Runner（GitLab Runner） | pipelineascode 的 Runner |
|---|---|---|
| Runner 是什么 | 一台常驻虚拟机/容器 | 一个临时的 Volcano Job Pod |
| 怎么分配任务 | Runner 主动认领 | Karmada 被动调度 |
| 需要 NPU 时 | 专门配一台带 NPU 的 Runner 机器 | CP_runs_on 写 `910b4-2`，自动分到有 NPU 的集群 |
| 任务结束 | Runner 继续跑下一个 | Pod 销毁，资源释放 |
| 隔离性 | 多个 Pipeline 共用同一台 Runner（可能互相影响） | 每个 Job 一个独立 Pod，完全隔离 |

### 一句话

**传统 Runner 是"长工"（常驻，等活干）—— pipelineascode 把它换成了"临时工"（每次来活现招一个，干完就散）。** 好处是不用维护 Runner 机器，按需占资源，NPU 用完立刻释放给别人。

---

## ECS

### 通俗理解

ECS（Elastic Cloud Server，弹性云服务器）= **云上的虚拟机**。

把 K8s 集群想像成一栋办公大楼，每个 Worker Node 就是一个工位。工位不够了怎么办？大楼经理打电话给物业："再给我加 20 个工位。"物业从隔壁空楼层搬 20 套桌椅过来——这 20 套桌椅就是 **ECS**。

### 在 pipelineascode 里它怎么影响你

你不需要直接操作 ECS。但你写的 `CP_runs_on` 间接决定了"会不会弹 ECS"：

```
你写 CP_runs_on="arm64-cpu-12-mem-48G-910b4-2"
  → converter 生成 Volcano Job，请求 2 颗 NPU
  → submit 提交到 Karmada → 路由到 wlcb 集群
  → wlcb 的 Volcano Scheduler 发现有 2 颗空闲 NPU → 直接调度 ✓

但如果：wlcb 所有 NPU 节点都满了
  → Pod 变成 Pending
  → 节点弹性策略（HNA）检测到资源不足
  → HNA 向华为云 API 发请求："开一台带 NPU 的新 ECS"
  → 几分钟后新 ECS 就绪，加入集群
  → Pending Pod 被调度上去
```

**所以 ECS 是兜底机制**——正常情况下不需要，只有当集群算力不够时才会自动弹。

### 和你经常看到的现象

22 点批量弹 ECS 的报告里记录的正是这个：ascend-infra 流水线在 22 点前后大量提交 NPU 作业 → 集群 CPU/内存瞬间打满 → HNA 每次 +1 台、反复触发 → 短时间弹出 20+ 台。ECS 本身不是问题，作业集中涌入才是根因。

### 一句话

**ECS = 集群工位不够用时，HNA 自动向云平台临时租的虚拟机。** 你只管写 `CP_runs_on`，集群自己会判断要不要弹。

---

## HNA

### 通俗理解

HNA（HorizontalNodeAutoscaler，节点水平伸缩）= **集群的自动招工规则**。

你是工厂老板。你定了一条规矩："只要工厂 CPU 利用率超过 80%，HR 就自动招一个临时工进来。"这条规矩就是 HNA。不用你盯着派人，机器自己数人头、自己招。

### 在 pipelineascode 里它怎么工作

HNA 绑定在节点池（NodePool）上，持续监控池里所有节点的资源用量：

```
正常状态：
  集群 10 个节点，CPU 平均 40%
  → HNA 不动

作业高峰（比如 22:00 ascend-infra 批量提交）：
  大量 Volcano Job Pending → Pod 占满现有节点
  → CPU 飙到 85%
  → HNA 触发："CPU>80%，加一台！"
  → 向华为云 API 申请新 ECS
  → 新节点就绪 → Pending Pod 被调度
  → 如果还不够 → HNA 再次触发 → 再加一台
  → 循环……
```

### 两种触发方式

| 类型 | 说明 | 你环境的实际情况 |
|------|------|----------------|
| Metric（指标） | CPU/内存超过阈值触发 | 你环境中唯一实际生效的类型 |
| Cron（定时） | 每天固定时间弹（如每晚 22 点预先扩） | 你环境中**没有**定时规则 |

所以 22 点弹 ECS 不是因为"设了 22 点弹"，而是 22 点的作业涌入触发了指标规则。

### 为什么一次弹了 20+ 台

规则设计问题，存在**放大效应**：

| 问题 | 后果 |
|------|------|
| 每次只 +1 台 | 作业持续涌入 → 一次不够 → 再触发 → 再 +1 → 滚雪球 |
| 无上限（max） | 不会弹到"够了"就停，只要指标不达标就一直加 |
| 无冷却窗口 | 刚弹完一台立刻评估，发现还不够，马上再弹 |
| 新 ECS 有 3-5 分钟就绪延迟 | 调度器以为资源始终不够，实际新节点马上就到 |

**举个具体例子**：22:00 涌入 100 个需要 NPU 的作业 → 20 个能立刻调度到已有节点 → 剩下 80 个 Pending → CPU 100% → HNA 触发 +1 → 3 分钟后新节点就绪，调走 2 个 Pod → CPU 还是 99% → 再触发 +1 → ……直到弹出 20+ 台才稳定。

### 怎么查 HNA

```bash
# kubectl
kubectl --context prod-0001 get horizontalnodeautoscalers -n kube-system

# k9s
:horizontalnodeautoscalers → 选中 → y 看规则 / d 看状态
```

### 一句话

**HNA = 集群不够用了，自动给云平台打电话："再来一台 ECS！"** 22 点弹 20+ 台不是 bug，是规则缺少上限和冷却的副作用——作业集中涌入 + 每次只加 1 台 = 滚雪球。

---

## ClusterPropagationPolicy (CPP)

### 通俗理解

pp 是管"argo 这个命名空间的东西去哪"，**cpp 是管"整个集群所有命名空间的东西去哪"**。

一句话区分：pp 是小区级派件规则，cpp 是所有小区的默认派件规则。

### 和 pp 的优先级

```
CPP 先扫："所有 Volcano 类型的资源，默认发到全部集群"
  ↓
PP 后扫："等等，argo 命名空间的，只发到 0001"
  ↓
最终：argo 命名空间的 Volcano Job → 只发 0001（pp 覆盖了 cpp）
```

**cpp 是兜底，pp 可以覆盖 cpp。** 优先级高的 pp 会抢走匹配权。

### 典型场景

在你环境的 `prod-guiyang-karmada` 上：

```bash
:cpp  # 在 k9s 上查看所有集群级策略
```

常见的 cpp 包含：
- `default-job-dispatch-policy`：所有 Volcano Job 默认发到全部成员集群
- `default-deployment-dispatch-policy`：所有 Deployment 默认发到全部成员集群

### 一句话

**cpp = 集群级的"默认发到哪"，pp = 命名空间级的"这个 ns 例外处理"。** 日常只用 :pp 看看有问题没有；`kubectl get cpp` 当你想知道"为什么这个 Job 被莫名其妙复制到某个集群了"才用。

---

## ClusterOverridePolicy (COP)

### 通俗理解

pp / cpp 只决定"往哪发"，**cop 决定"发过去之前要不要改点什么"**。

就像寄快递：pp 决定了发往"深圳仓库"，cop 决定了"到深圳仓库之后，收货地址从上海市改成深圳市"——目的地自己再根据本地情况做微调。

### 为什么需要 cop

多集群联邦里，不同集群的网络环境不一样：

| 集群 | 镜像仓库访问方式 |
|------|----------------|
| 0001 | `swr.cn-north-4.myhuaweicloud.com`（公网） |
| guiyang | `10.0.1.x:5443`（内网更快） |

一个 Job YAML 里写了 `image: swr.cn-north-4.../pytorch-ascend:v2.2`，发到 0001 直接用没问题，但发到 guiyang 时走内网地址拉镜像会快很多。

**cop 做的事**：匹配到目标集群 → 在 YAML 落地前把镜像地址自动替换成该集群的最优地址。Karmada 把这个叫"imageOverride"。

### 在 pipelineascode 里你会遇到它吗

一般不会。cop 是运维预先配好的（类似基础设施层的配置），你的 shell.sh 和 env.sh 里不用管。只有当你发现"同一个 Job 在 0001 跑得通、在 guiyang 报 ImagePullBackOff"时，才可能是 cop 没配或配错了。

### 一句话

**cop = pp 决定去哪，cop 决定到了之后怎么微调。** 大部分时候你不需要管它，只有"同一个 Job 在不同集群行为不一样"时才是排查方向。

