# 正式贵阳 Karmada 成员集群对比：001 vs wlcb

- **控制面**：`prod-guiyang-karmada`（1.95.223.182:5443）
- **成员集群**：`001`（`prod-0001`）、`wlcb`（`prod-wlcb`），均为 Push 模式、Ready
- **取证时间**：2026-07-09（数据为实时快照，节点数会随弹性伸缩波动）

---

## 一、结论速览

- **001**：大规模、异构（910b/310p/CPU）、带弹性 ECS 的**主力混合集群**，承接非 NPU 批作业与潮汐负载（22 点弹 ECS 现象即发生在此）。
- **wlcb**：小而专、以固定物理 910b（313t）NPU 机为主的**精简算力集群**，基本不做弹性伸缩。

---

## 二、核心对比表

| 维度 | **001**（`prod-0001`） | **wlcb**（`prod-wlcb`） |
|------|------------------------|--------------------------|
| API Server | 101.245.109.198:5443 | 1.92.221.43:5443 |
| K8s 版本 | v1.31.14-r0-**31.0.62** | v1.31.10-r30-**31.0.44.11**（略旧一档） |
| 节点总数 | **58** | **11** |
| NPU 训练卡 `huawei.com/ascend-1980` | **80 张** | **64 张** |
| 推理卡 `huawei.com/ascend-310` | **8**（另有 310p 节点） | 无 |
| 弹性 ECS 节点 | 大量（arm/x86 nodepool，高峰新弹数十台） | 极少（快照时仅 1 台） |
| 物理 NPU 机型 | kat2e.48xlarge **280t / 400t** | kat2e.48xlarge **313t** |
| 节点角色标签 | 明确分层（见下） | 基本无角色标签，几乎全为物理 NPU 机 |
| 弹性节点池 | `arm-nodepool-15162`、`x86-nodepool-36698` | `x86-nodepool-59550`（规模小） |

---

## 三、节点构成明细

### 001（58 节点，异构分层）

| 角色 / 类型 | 数量 | 机型示例 |
|-------------|------|----------|
| `ascend-910b4` | 6 | physical.kat2e.48xlarge.8.**280t** |
| `ascend-910b1` | 4 | physical.kat2e.48xlarge.8.**400t** |
| `ascend-310p` | 1 | kai2p.24xlarge.4（推理卡） |
| `cpu-arm-128u` | 4 | kc2.32xlarge.4 |
| `cpu-x86-128u` | 5 | c7.32xlarge.4 |
| `cpu-x86-64u` | 1 | c7.16xlarge.2 |
| 无角色标签（多为弹性 ECS） | 37 | arm-nodepool `kc2.*` / x86-nodepool `ac8.32xlarge.4` |

- NPU 总量：`ascend-1980` 80 张 + `ascend-310` 8。
- 大量 `<none>` 角色节点来自 `arm-nodepool-15162` / `x86-nodepool-36698` 弹性池，Age 多为几十分钟，随负载弹性增减。

### wlcb（11 节点，NPU 专用）

| 类型 | 数量 | 机型 |
|------|------|------|
| 物理 NPU 机 | 9 | physical.kat2e.48xlarge.8.**313t** |
| CPU 机 | 2 | c7.16xlarge.2 / c6s.4xlarge.2 |
| 弹性 ECS | 1（快照时） | x86-nodepool-59550 `ac7.32xlarge.4` |

- NPU 总量：`ascend-1980` 64 张。
- 9 台物理 NPU 机 Age 多为 96 天，属固定算力池，几乎不弹性伸缩。

---

## 四、定位与调度差异

### 001 = 主力混合集群 / 弹性计算池
- 规模最大、机型最全（训练卡 910b1/b4 + 推理卡 310p + CPU + 弹性 ECS）。
- Karmada 把**非 NPU 批作业优先/强制**派到这里：
  - `non-npu-vcjob-prefer-001`（ClusterPropagationPolicy，priority 20）：非 NPU vcjob 优先落 001。
  - `non-npu-vcjob-node-affinity`（ClusterOverridePolicy）：给下发到 001 的非 NPU 作业注入
    nodeAffinity（`accelerator/huawei-npu DoesNotExist`），强制其只上非 NPU 节点，保护 NPU 卡节点。
- 因此 **22 点批量弹 ECS 的现象发生在 001**——它是承接弹性/潮汐负载的集群
  （详见 `22点弹ECS诊断报告.md`）。

### wlcb = 精简 NPU 专用集群
- 以固定物理 910b（313t）NPU 机为主，基本不弹性扩容。
- 有独立的 `wlcb-pod-policy`（ClusterPropagationPolicy，priority 100）约束其上 Pod 调度。
- K8s 版本比 001 旧一档。

---

## 五、节点计费模式：pre-paid vs post-paid（`node.cce.io/billing-mode`）

001 节点带 `node.cce.io/billing-mode` 标签，快照时分布：**pre-paid 21 台、post-paid 32 台**。
这对应你观察到的"固定机器"与"创建不久的机器"。

| | **pre-paid（包年包月/预付费）** | **post-paid（按需/后付费）** |
|---|---|---|
| 付费方式 | 先付费、整包购买 | 后付费、按使用时长计费（按秒/小时） |
| 单价 | 低（有折扣） | 高 |
| 生命周期 | 长期常驻，不自动回收 | 临时弹性，用完即释放 |
| 对应节点 | Age 长、有 role 标签（ascend-910b/x86/arm） | Age 短、role=`<none>`、来自弹性节点池 |
| 定位 | 基线固定算力（NPU 训练卡、核心 CPU 池） | 波峰弹性算力（Karpenter/HNA 弹出的 ECS） |
| 本集群体现 | 21 台固定 NPU/CPU 底座 | 32 台弹性 ECS |

**成本关联**：22 点弹出的正是 **post-paid 按需 ECS**——单价贵、按量计费。夜间批作业高峰频繁弹
数十台 post-paid 机器，成本会显著高于 pre-paid 常驻或错峰削峰，这也是诊断报告中建议"对夜间固定
批次用预留/包周期节点替代高峰实时弹 ECS"的原因（见 `22点弹ECS诊断报告.md` P2）。

```bash
# 查看 001 各节点计费模式分布
kubectl --context prod-0001 get nodes -L node.cce.io/billing-mode
```

---

## 六、相同点

- 同属 `prod-guiyang-karmada` 控制面，Push 模式接入，状态 Ready。
- 命名空间结构基本一致：`argo` / `pytorch` / `mindie-*` / `indexsdk` / `recsdk` /
  `op-plugin` / `volcano-global` / `monitoring` / `harbor` / `git-cache` 等。
- 均运行 Volcano 批作业调度，作业由 Karmada 从控制面下发。

---

## 七、复核命令

```bash
# 控制面看两个成员集群
kubectl --context prod-guiyang-karmada get clusters -o wide

# 节点构成（角色 / 节点池 / 机型 / 架构）
kubectl --context prod-0001 get nodes -L cce.cloud.com/cce-nodepool,node.kubernetes.io/instance-type,kubernetes.io/arch
kubectl --context prod-wlcb  get nodes -L cce.cloud.com/cce-nodepool,node.kubernetes.io/instance-type,kubernetes.io/arch

# NPU 卡总量
kubectl --context prod-0001 get nodes -o json | \
  python3 -c "import json,sys;d=json.load(sys.stdin);print(sum(int(n['status']['capacity'].get('huawei.com/ascend-1980',0)) for n in d['items']))"

# 相关调度策略（控制面）
kubectl --context prod-guiyang-karmada get cpp | grep -Ei "001|wlcb|non-npu"
kubectl --context prod-guiyang-karmada get cop non-npu-vcjob-node-affinity -o yaml
```

> 注：节点数与弹性 ECS 数量为实时快照，会随负载潮汐变化；NPU 物理机数量相对稳定。
