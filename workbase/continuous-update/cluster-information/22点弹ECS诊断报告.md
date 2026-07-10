# 正式集群 22:00 批量弹出 ECS 诊断报告

- **诊断对象**：正式生产集群 `prod-0001`（CCE，API 101.245.109.198:5443）
- **现象**：每天约 22:00，`ascend-infra` 相关负载导致集群新建 20+ 台 ECS
- **诊断时间**：2026-07-09
- **诊断方式**：kubectl 直连各集群实时取证（context 见 `k9s使用说明.md`）

---

## 一、结论速览（TL;DR）

1. **ECS 不是"定时规则"弹出来的**。集群里唯一的节点弹性规则是**指标触发型**（CPU>80% 或 内存>80%），没有任何 cron/定时规则。
2. **真正触发是 22:00 的一批 CI 构建作业**。Argo + Karmada 在 22 点前后批量下发大量 `ascend-*` Volcano 作业（vcjob），来源是 Ascend 各代码仓（pytorch / indexsdk / torchair / mind-cluster / mindie 等）的流水线，即你说的 **ascend-infra** 基础设施流水线。
3. **弹性规则是"帮凶"不是"元凶"**：作业涌入 → 大量 Pending Pod → CPU/内存打满 → 指标规则每次 +1 台、反复触发 → 短时间滚出 20+ 台 ECS。
4. **规则设计有放大效应**：纯指标、每次仅 +1、无上限约束、无冷却窗口，导致一次负载高峰被拆成几十次连续扩容。

---

## 二、环境事实（取证数据）

### 2.1 节点弹性组件
`prod-0001` 使用华为 CCE 节点弹性方案：

| 组件 | 位置 | 说明 |
|------|------|------|
| `karpenter-provider-huawei-controller-manager` | ns `karpenter` | 华为版 Karpenter 节点供给控制器（Running） |
| `HorizontalNodeAutoscaler`（HNA） | ns `kube-system` | CCE 原生节点伸缩策略，绑定节点池 |

> 注：`kubectl get nodepools.karpenter.sh` / `ccenodeclasses` 返回空，实际生效的是下面两条 **HNA** 策略。

### 2.2 当前弹出规则（两条 HNA，均为指标触发）

| 策略名 | 绑定节点池 ID | 规则 | 动作 |
|--------|---------------|------|------|
| `policy-1780919068541` | `03f0089c-632e-11f1-9935-0255ac100049` | CPU>80% / 内存>80% | ScaleUp **1 Node** |
| `policy-1780919153912` | `2306564e-632f-11f1-9dca-0255ac1000f2` | CPU>80% / 内存>80% | ScaleUp **1 Node** |

关键点：
- `spec.rules[*].type = Metric`，**无 `type: Cron` / 定时规则**
- 每条规则 `action.value = 1`（一次只加 1 台）
- **无扩容上限、无冷却时间配置**

### 2.3 扩容记录印证 22:00 高峰（policy-1780919068541 status 摘录）

| 探测时间 (UTC) | 北京时间 | 结果 | 节点数变化 |
|----------------|----------|------|-----------|
| 2026-07-08T12:14:01Z | 20:14 | Successful | 2 → 3 |
| 2026-07-08T12:18:17Z | 20:18 | Successful | 4 → 5 |
| **2026-07-08T14:11:09Z** | **22:11** | Successful | 7 → 8 |
| **2026-07-08T14:11:32Z** | **22:11** | Successful | 8 → 9 |
| 2026-07-08T16:04:41Z | 次日 00:04 | Successful | 7 → 8 |
| 2026-07-08T16:55:12Z | 次日 00:55 | Successful | 9 → 10 |

> 22 点前后出现连续、密集的 `increase 1 node`，与现象吻合。

### 2.4 另一节点池存在"抢不到 ECS 规格"失败（policy-1780919153912）

status 中多次出现：

```
failed to increase node group size: StatusCode 400,
errorCode CCE.01400021, "No available flavors for nodes",
insufficient flavor: kc2.32xlarge.4 / kc2.20xlarge.4,
availableZone: cn-southwest-2f / 2d,
reason: ECSResourcesInsufficient
```

说明高峰期部分可用区**大规格 ECS 库存不足**，弹性器会跨规格/跨 scaleGroup 重试，进一步放大 ECS 创建次数与失败噪音。

---

## 三、22:00 负载来源分析

### 3.1 负载类型：Volcano 批作业（vcjob）
集群短时间内持续创建大量 `ascend-*` vcjob，分布在 `argo` / `op-plugin` / `indexsdk` / `recsdk` 等命名空间：

```
argo       ascend-mind-cluster-*     shared-flexible-queue
argo       ascend-torchair-*         shared-flexible-queue
argo       ascend-mindie-pymotor-*   shared-flexible-queue
argo       ascend-indexsdk-*         large-task-shared-queue
op-plugin  ascend-pytorch-*          shared-flexible-queue
```

Volcano 队列（`kubectl get queue`）：`default` / `large-task-shared-queue` / `shared-flexible-queue`（均挂在 `root` 下）。

### 3.2 作业来源：CI 流水线经 Karmada 下发
取样 vcjob `op-plugin/ascend-pytorch-*` 的标签与 env 证实作业由 **CI 流水线**产生，并经 **Karmada** 下发到成员集群 `001`：

```yaml
labels:
  jobRepositoryName: ascend-pytorch
annotations:
  resourcetemplate.karmada.io/managed-labels: >-
    clusterpropagationpolicy.karmada.io/permanent-id, dispatch/001,
    jobPRID, jobRepositoryName, pipeline/run-id,
    resourcebinding.karmada.io/permanent-id, ...
env:
  __repository__: '{"repo_name":"pytorch","url":"https://gitcode.com/Ascend/pytorch.git"}'
  # 触发源 argo，CLOUD_BUILD_REPO_URL ...
```

对应链路：

```
ascend-infra 流水线(Argo, 22:00 批次)
        │  按仓库(pytorch/indexsdk/torchair/...)生成 vcjob
        ▼
Karmada 控制面 (prod-guiyang-karmada)
        │  default-job-dispatch-policy (priority 10) → dispatch/001
        ▼
成员集群 001 (prod-0001)  —— 大量 Pending Pod
        │  抢占 NPU/CPU/内存，利用率 > 80%
        ▼
HorizontalNodeAutoscaler (Metric) —— 每次 +1，反复触发
        ▼
CCE 节点池扩容 → 创建 20+ ECS
```

> 相关 Karmada 调度策略（在 `prod-guiyang-karmada` 控制面）：
> `default-job-dispatch-policy`(priority 10)、`non-npu-vcjob-prefer-001`(priority 20)、
> `volcano-global-dispatch-policy` 等，负责把作业分发/倾向到成员集群 `001`。

### 3.3 当前节点池构成（诊断时刻，共约 31 个节点）

| 节点池 / 类型 | 数量 | 规格示例 |
|---------------|------|----------|
| `arm-nodepool-15162` | 6 | kc2.20xlarge.2（弹性 ECS） |
| `x86-nodepool-36698` | 4 | ac8.32xlarge.4（弹性 ECS） |
| 无池标签（静态物理机） | 多 | physical.kat2e.48xlarge.8.280t（ascend-910b4） |

弹性 ECS 主要落在 `arm-nodepool` / `x86-nodepool`，NPU 训练卡为固定物理节点。

---

## 四、根因判定

| 层级 | 是否根因 | 说明 |
|------|----------|------|
| HNA 弹性规则 | ❌ 非根因（执行者） | 忠实执行"利用率>80%就加机器"，但设计放大了扩容次数 |
| 22:00 CI 作业批次 | ✅ **直接触发** | ascend-infra 流水线夜间批量生成 vcjob，制造负载尖峰 |
| Karmada 下发策略 | ➖ 传导环节 | 把作业集中派发到 `001`，加剧单集群峰值 |
| ECS 规格库存 | ➖ 次生问题 | 高峰期部分 AZ 规格不足，触发跨组重试，放大噪音 |

**一句话**：22 点的 ECS 潮汐是"**CI 夜间批量作业**"打出来的负载尖峰，被"**纯指标、无上限、每次+1**"的节点弹性规则反应式地放大成了 20+ 台 ECS。

---

## 五、处置建议（按优先级）

### P0 — 削峰（治本，控制作业侧）
- 让 `ascend-infra` 流水线的 22:00 批次**错峰/限流**：限制 Argo 并发（`parallelism`）、分批提交。
- 给 Volcano 队列设 `capability` 上限（`large-task-shared-queue` / `shared-flexible-queue`），把峰值封顶在可控算力内，让作业排队而非无脑扩容。

### P1 — 给弹性规则加"刹车"（治标，控制扩容侧）
- 为两条 HNA 绑定的节点池设置**最大节点数上限（max）**。
- 增加**扩容冷却/静默窗口**，避免一次高峰被拆成几十次 +1。
- 评估把 `action.value` 从 1 改为按缺口批量扩容，或改用**按队列 Pending 量**的伸缩信号（CPU/内存 80% 对"排队等 NPU"的批作业并不准确，易误判打满）。

### P2 — 容量与规格
- 对夜间固定批次，考虑**预留固定容量 / 包周期节点**替代高峰实时弹 ECS，规避 `ECSResourcesInsufficient`。
- 核对 `policy-1780919153912` 节点池的可用区/规格配置，减少 `No available flavors` 失败重试。

---

## 六、复现 / 复核命令

```bash
# 1) 查看两条弹性规则完整定义与扩容历史
kubectl --context prod-0001 get horizontalnodeautoscaler -n kube-system -o yaml

# 2) 按创建时间看 22:00 前后涌入的 vcjob 及队列
kubectl --context prod-0001 get vcjob -A \
  --sort-by=.metadata.creationTimestamp \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,\
CREATED:.metadata.creationTimestamp,QUEUE:.spec.queue

# 3) 查某作业来源（仓库 / 流水线 / Karmada 下发标签）
kubectl --context prod-0001 get vcjob -n op-plugin <job-name> -o yaml | \
  grep -iE "jobRepositoryName|repository|pipeline|dispatch|argo"

# 4) 查节点池分布与弹性 ECS
kubectl --context prod-0001 get nodes -L cce.cloud.com/cce-nodepool

# 5) 查 Karmada 侧作业下发策略（在控制面）
kubectl --context prod-guiyang-karmada get cpp default-job-dispatch-policy -o yaml
kubectl --context prod-guiyang-karmada get pp -n default volcano-global-dispatch-policy -o yaml
```

---

## 附录 A：两条 HNA 规则原文（节选 spec）

```yaml
# policy-1780919068541  (节点池 03f0089c-632e-11f1-9935-0255ac100049)
spec:
  disable: false
  rules:
  - ruleName: rule88761
    type: Metric
    metricTrigger: { metricName: Cpu,    metricOperation: '>', metricValue: "80", unit: Percent }
    action: { type: ScaleUp, unit: Node, value: 1 }
  - ruleName: rule26091
    type: Metric
    metricTrigger: { metricName: Memory, metricOperation: '>', metricValue: "80", unit: Percent }
    action: { type: ScaleUp, unit: Node, value: 1 }
  targetNodepoolIds: [ 03f0089c-632e-11f1-9935-0255ac100049 ]

# policy-1780919153912  (节点池 2306564e-632f-11f1-9dca-0255ac1000f2)
spec:
  disable: false
  rules:
  - ruleName: rule48871
    type: Metric
    metricTrigger: { metricName: Cpu,    metricOperation: '>', metricValue: "80", unit: Percent }
    action: { type: ScaleUp, unit: Node, value: 1 }
  - ruleName: rule65468
    type: Metric
    metricTrigger: { metricName: Memory, metricOperation: '>', metricValue: "80", unit: Percent }
    action: { type: ScaleUp, unit: Node, value: 1 }
  targetNodepoolIds: [ 2306564e-632f-11f1-9dca-0255ac1000f2 ]
```

> 说明：两条规则均无 `Cron`/定时项，无 `max` 上限、无冷却窗口，`value` 固定为 1。
