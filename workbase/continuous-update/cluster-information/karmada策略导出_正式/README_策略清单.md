# Karmada 调度策略清单索引（正式贵阳 `prod-guiyang-karmada`）

- **导出时间**：2026-07-09
- **控制面**：`prod-guiyang-karmada`（1.95.223.182:5443）
- **成员集群**：`001`、`wlcb`
- **本目录**：策略原文 YAML 见 `cpp/`、`cop/`、`pp/` 子目录
- **统计**：18 × ClusterPropagationPolicy + 2 × ClusterOverridePolicy + 2 × PropagationPolicy（无 OverridePolicy）

> 匹配规则：一个资源可命中多条策略，Karmada 取 **priority 最高**且 resourceSelector 匹配的那条，其 `placement` 决定去哪个集群。

---

## 一、传播策略 · 分配类（决定作业去 001 还是 wlcb）

| 策略 | 优先级 | 命中条件 | 目标集群 | 副本策略 |
|------|:---:|------|------|------|
| `member1-pod-policy` | **100** | Pod/Job 带标签 `dispatch/001=true` | **001**（钉住） | — |
| `wlcb-pod-policy` | **100** | Pod/Job 带标签 `dispatch/wlcb=true` | **wlcb**（钉住） | — |
| `non-npu-vcjob-prefer-001` | **20** | Job/vcjob 且 `huawei.com/npu` 不存在（非 NPU） | **001** | Divided / Aggregated |
| `default-job-dispatch-policy` | **10** | Job/vcjob 且无 `dispatch/001`、`dispatch/wlcb` 标签 | **001 + wlcb** | Divided / Aggregated |

**分配走向**（优先级从高到低短路匹配）：
```
dispatch/001=true → 001         (p100)
dispatch/wlcb=true → wlcb       (p100)
非 NPU 作业        → 001         (p20)
其余(NPU/未钉)     → 001+wlcb 按容量分  (p10)
```

---

## 二、传播策略 · 命名空间下发类（把 ns 铺到两个集群）

| 策略 | 优先级 | 命中 | 目标 | 副本策略 |
|------|:---:|------|------|------|
| `argo-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `pytorch-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `indexsdk-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `recsdk-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `ragsdk-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `op-plugin-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `fbgemm-ascend-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `multimodalsdk-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `mindie-llm-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `mindie-motor-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |
| `mindie-sd-namespace-propagation` | 0 | Namespace | 001 + wlcb | Duplicated |

> `Duplicated` = 该命名空间在两个集群各建一份（不是拆分），保证两集群都有对应 ns。

---

## 三、传播策略 · 其它类

| 策略 | 优先级 | 命中 | 目标 | 说明 |
|------|:---:|------|------|------|
| `member1-secret-policy` | 100 | Secret 带 `dispatch/001=true` | 001 | 定向下发密钥到 001 |
| `member2-secret-policy` | 100 | Secret 带 `dispatch/wlcb=true` | wlcb | 定向下发密钥到 wlcb |
| `volcano-global-all-queue-propagation` | 0 | Volcano `Queue` | 未指定 clusterAffinity（Duplicated） | 下发 Volcano 全局队列 |

> 注：`volcano-global-all-queue-propagation` 的 placement 只有 `replicaScheduling: Duplicated`、**未写 clusterAffinity**，建议核对是否符合预期（正常应显式指定目标集群）。

---

## 四、改写策略（ClusterOverridePolicy · 下发时修改资源）

| 策略 | 目标集群 | 命中条件 | 改写动作 | 作用 |
|------|------|------|------|------|
| `non-npu-vcjob-node-affinity` | **001** | Job 且 `huawei.com/npu` 不存在（非 NPU） | `add` `/spec/tasks/0/template/spec/affinity` | 给非 NPU 作业注入 nodeAffinity，强制只上**非 NPU 节点**（保护 NPU 卡） |
| `kunpeng-arm-vcjob-node-selector` | 全部集群 | Job 且非 NPU 且 `arch in (arm64,arm)` | `replace` `/spec/tasks/0/template/spec/nodeSelector` | 给鲲鹏 ARM 非 NPU 作业改写 nodeSelector，定向到 ARM 节点 |

> 两条 cop 的改写路径都写死在 `/spec/tasks/0`，**多 task 的 vcjob 只有第一个 task 生效**（扩展/修改时需注意，见 `调度优化方案_固定机优先.md` 局限说明）。

---

## 五、命名空间级传播策略（PropagationPolicy）

| 策略 | 命名空间 | 优先级 | 命中 | 目标集群 | 说明 |
|------|------|:---:|------|------|------|
| `argo-npuir-policy` | `argo` | 20 | argo 下资源 | **wlcb** | 把 argo 的 NPU-IR 相关作业定向到 wlcb |
| `volcano-global-dispatch-policy` | `default` | 0 | default 下资源 | 未指定 clusterAffinity | Volcano 全局分发（兜底） |

---

## 六、优先级全景（数值越大越先匹配）

```
100  member1-pod-policy / wlcb-pod-policy / member1-secret-policy / member2-secret-policy   (显式钉集群)
 20  non-npu-vcjob-prefer-001 (cpp)  /  argo-npuir-policy (pp, argo→wlcb)
 10  default-job-dispatch-policy      (兜底分配)
  0  各 *-namespace-propagation / volcano-global-* / volcano-global-dispatch-policy
```

---

## 七、值得关注的点

1. **非 NPU 作业单钉 001**：`non-npu-vcjob-prefer-001` 现状 `clusterAffinity` 只有 `001`（无 wlcb 兜底），是 22:00 弹 ECS 的分配根源（见 `22点弹ECS诊断报告.md`）。
2. **集群名硬编码**：分配类与 ns 下发类策略普遍写死 `["001","wlcb"]`，新增集群需改多处（改造建议见 `调度策略标签化改造方案.md`）。
3. **两条 override 仅作用于 `tasks[0]`**：多 task 作业需留意。
4. **两处 placement 缺 clusterAffinity**：`volcano-global-all-queue-propagation`、`volcano-global-dispatch-policy` 未显式指定目标集群，建议核对。

---

## 八、重新导出/复核命令

```bash
ctx=prod-guiyang-karmada
kubectl --context $ctx get cpp
kubectl --context $ctx get cop
kubectl --context $ctx get pp -A
# 单条查看
kubectl --context $ctx get cpp <name> -o yaml
kubectl --context $ctx get cop <name> -o yaml
# 调度结果
kubectl --context $ctx get rb -A
```
