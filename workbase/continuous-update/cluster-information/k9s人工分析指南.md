# k9s 人工分析操作指南（正式/测试多集群 + Volcano + Karmada）

> 面向本环境（华为 CCE + Volcano 批作业 + Karmada 多集群 + Karpenter/HNA 节点弹性）的实战排查手册。
> 集群 context 清单见 `k9s使用说明.md`；本文侧重"进去之后怎么一步步查问题"。

---

## 0. 心智模型：k9s 怎么用

k9s 是一个"资源浏览器 + 实时监控台"。核心循环是：

```
:资源类型   →   选中某行   →   看详情/日志/YAML   →   Esc 返回
```

- 冒号 `:` = 命令模式（切资源、切集群、切命名空间）
- 斜杠 `/` = 在当前列表里过滤
- 每个界面右上角/底部会提示可用快捷键
- 一切只读为主，误操作风险低；删除/编辑需要显式按键并确认

---

## 1. 启动与全局导航

```bash
k9s                                   # 用当前默认 context
k9s --context prod-0001               # 指定集群启动
k9s --context prod-0001 -n argo       # 指定集群 + 命名空间
k9s --context prod-0001 -c pod        # 启动即进入 pod 视图
```

### 全局快捷键（任何界面都可用）

| 按键 | 作用 |
|------|------|
| `:` | 进入命令模式，输入资源名/别名跳转 |
| `/` | 在当前列表内过滤（支持正则，如 `/ascend-pytorch`） |
| `Esc` | 返回上一级 / 取消过滤 |
| `?` | 显示当前视图的快捷键帮助 |
| `:q` 或 `Ctrl+C` | 退出 k9s |
| `0`–`9` | 快速切命名空间（`0` = 所有 ns） |
| `Tab` / 方向键 | 在列表/面板间移动 |
| `Enter` | 进入选中项（下钻） |
| `Ctrl+A` | 列出所有可访问的资源类型（aliases 视图） |

### 切集群 / 切命名空间

```
:ctx            # 列出所有集群 context，回车切换
:ns             # 列出命名空间，回车切换
```

---

## 2. 常用资源别名速查

命令模式下输入这些（k9s 支持简写和 CRD 全名）：

| 输入 | 资源 |
|------|------|
| `:pod` / `:po` | Pod |
| `:deploy` | Deployment |
| `:sts` | StatefulSet |
| `:svc` | Service |
| `:node` / `:no` | 节点 |
| `:ns` | 命名空间 |
| `:ev` / `:events` | 事件（排障最重要） |
| `:job` | 原生 Job |
| `:cj` / `:cronjob` | CronJob |
| `:hpa` | Pod 水平伸缩 |
| `:pvc` / `:pv` | 存储卷 |
| `:cm` | ConfigMap |
| `:secret` | Secret |
| `:rb` | RoleBinding（注意与 Karmada rb 区分，见下） |

### 本环境专用 CRD（直接输全名）

| 输入                                     | 资源                 | 用途                       |
| -------------------------------------- | ------------------ | ------------------------ |
| `:horizontalnodeautoscalers`           | HNA 节点弹性规则         | 查 ECS 弹出规则               |
| `:nodepools`                           | Karpenter NodePool | 节点池                      |
| `:ccenodeclasses`                      | CCE 节点类            | 节点规格模板                   |
| `:vcjob` / `:jobs.batch.volcano.sh`    | Volcano 作业         | 批作业排查（重点）                |
| `:queues` / `:q`                       | Volcano 队列         | 队列容量/排队                  |
| `:propagationpolicies` / `:pp`         | Karmada 传播策略       | 多集群下发（仅 karmada context） |
| `:clusterpropagationpolicies` / `:cpp` | Karmada 集群级策略      | 同上                       |
| `:resourcebindings` / `:rb`            | Karmada 调度结果       | 资源被派到哪些成员集群              |
| `:clusters`                            | Karmada 成员集群       | 仅 karmada context        |
| `:workflows` / `:wf`                   | Argo Workflow      | CI 流水线运行实例               |
| `:cronworkflows` / `:cwf`              | Argo 定时流水线         | 定时任务源头                   |

> 记不住全名时，按 `Ctrl+A` 打开 aliases 视图，用 `/` 搜关键字（如 `/node`、`/karmada`）。

---

## 3. 选中某行后的操作键

在任意资源列表里选中一行后：

| 按键 | 作用 |
|------|------|
| `Enter` | 下钻（如 Deployment → 其 Pod） |
| `d` | describe（看详情、事件、状态原因） |
| `y` | 查看完整 YAML |
| `l` | 看日志（Pod/容器）|
| `s` | 进入容器 shell |
| `e` | 编辑（谨慎，会改线上） |
| `Ctrl+D` | 删除（会二次确认，生产慎用） |
| `Ctrl+K` | kill（强制删 Pod） |
| `Shift+字母` | 按该列排序（如节点视图 `Shift+C` 按 CPU） |

### 看日志时的子操作
- `0` 全部 / `1`–`9` 最近 N 行
- `f` 切换全屏
- `w` 切换换行
- `s` 切换 autoscroll（实时跟随）
- `/关键字` 过滤日志行

---

## 4. 实战：针对本环境的排查套路

### 套路 A：排查"22 点弹 ECS"这类节点弹性问题

```
k9s --context prod-0001
:horizontalnodeautoscalers        # 看有几条弹性规则
  → 选中 policy-xxx → y            # 看 spec：是 Metric 还是 Cron？阈值多少？有无 max
  → 选中 policy-xxx → d            # 看 status.conditions：每次扩容的时间戳与结果
:node                             # Shift+C / Shift+M 按 CPU/内存排序，看谁被打满
  → 选中高负载节点 → d             # 看该节点上的 Pod 和资源分配
:ev                               # 过滤 /Scale 或 /Insufficient，看扩容/库存不足事件
```

判断要点：
- HNA 的 `spec.rules[].type` 是 `Metric`（指标）还是 `Cron`（定时）
- `action.value`（每次加几台）、有无节点池 `max` 上限
- `status.conditions[].lastProbeTime` 换算北京时间（UTC+8）看高峰时刻
- 有无 `ECSResourcesInsufficient` / `No available flavors` 失败

### 套路 B：排查"哪来这么多作业"（Volcano vcjob）

```
:vcjob                            # 0 切到所有命名空间
  → 按 Age 排序看最近涌入的批次
  → /ascend-pytorch               # 过滤某类作业
  → 选中某 vcjob → y              # 看 labels：jobRepositoryName / pipeline/run-id / dispatch/001
  → 选中某 vcjob → d              # 看 status：Running/Pending/失败原因
:queues                           # 看队列容量与排队情况
  → 选中队列 → y                  # 看 spec.capability（是否设了上限）
:pod                              # /Pending 过滤，看多少 Pod 卡在等资源
  → 选中 Pending Pod → d          # Events 里看 "Insufficient npu/cpu" 之类原因
```

判断要点：
- vcjob 的 `spec.queue` 落在哪个队列（`shared-flexible-queue` / `large-task-shared-queue`）
- labels 里的 `jobRepositoryName`、`pipeline/run-id` = 作业来自哪个仓库/流水线
- `dispatch/001` 等 Karmada 标签 = 由控制面下发而非本地创建

### 套路 C：多集群调度分析（Karmada）

```
k9s --context prod-guiyang-karmada
:clusters                         # 看成员集群 001 / wlcb 状态、Ready、Mode
:cpp                              # 集群级传播策略
  → 选中 default-job-dispatch-policy → y   # 看 placement：目标集群/权重/优先级
:pp                               # 0 切所有 ns，看命名空间级策略
:rb                               # ResourceBinding = 某资源实际被调度到哪些集群
  → 选中 → y                      # spec.clusters 里是分派结果
```

判断要点：
- `placement.clusterAffinity` / `spreadConstraints` / `replicaScheduling` 决定作业往哪派、怎么摊
- `priority` 高的策略优先匹配（如 `member1-pod-policy` priority 100）
- 对照成员集群实际负载，判断是否派发不均导致单集群被打爆

### 套路 D：通用故障定位（Pod 起不来 / 报错）

```
:pod → 0（所有 ns）
  → /CrashLoop 或 /Error 或 /Pending    # 过滤异常 Pod
  → 选中 → d                             # 底部 Events 是第一手线索
  → 选中 → l                             # 看容器日志；多容器按 数字 切容器
:ev                                      # 全局事件流，/Warning 过滤告警
```

---

## 5. 资源用量与监控视图

| 命令/按键 | 作用 |
|-----------|------|
| `:node` 然后 `Shift+C` | 按 CPU 使用排序节点 |
| `:node` 然后 `Shift+M` | 按内存排序 |
| `:pod` 然后 `Shift+C`/`Shift+M` | 按 Pod 用量排序，揪出吃资源大户 |
| `:pulse` | 集群健康脉搏面板（各资源计数/状态总览） |
| `:xray deploy` | 树状展开 Deployment→RS→Pod 关系 |
| `:popeye` | 集群体检（若装了 popeye 插件，查配置隐患） |

> 用量列（CPU/MEM 的 `%`）依赖 metrics-server；若显示 `n/a` 说明该集群没装或未就绪。

---

## 6. 过滤与搜索技巧

- `/关键字`：普通子串过滤
- `/!关键字`：反向过滤（排除）
- `/-l app=xxx` 或输入 labels 过滤（部分视图支持标签选择器）
- 命名空间快切：`:ns` 后回车，或列表界面按 `0`–`9`
- 在事件视图 `:ev` 里 `/Warning`、`/Failed`、`/Scale`、`/Insufficient` 是排障高频词

---

## 7. 只读安全提示

- **生产集群（prod-*）默认只看不动**：`e` 编辑、`Ctrl+D` 删除、`Ctrl+K` kill 都会改线上，务必确认 context 再操作。
- k9s 顶部会显示当前 **context 名 + 命名空间**，动手前先瞄一眼别切错集群。
- 想强制只读，可用只读模式启动：

```bash
k9s --context prod-0001 --readonly
```

- 切集群频繁时，善用 `:ctx` 而不是退出重开。

---

## 8. 一页速记（贴屏边）

```
切集群    :ctx            切命名空间  :ns / 0-9
弹性规则  :horizontalnodeautoscalers
批作业    :vcjob          队列        :queues
Karmada   :cpp :pp :rb :clusters   (需 karmada context)
节点排序  :node → Shift+C / Shift+M
事件      :ev  → /Warning /Scale /Insufficient
详情 d    YAML y    日志 l    Shell s    编辑 e(慎)
过滤 /    返回 Esc   帮助 ?    退出 :q
```

---

## 9. 与 kubectl 的对应（k9s 查到后想脚本化）

| k9s 操作 | kubectl 等价 |
|----------|--------------|
| `:horizontalnodeautoscalers` + `y` | `kubectl --context prod-0001 get hna -n kube-system -o yaml` |
| `:vcjob` 排序 | `kubectl --context prod-0001 get vcjob -A --sort-by=.metadata.creationTimestamp` |
| `:node` + `Shift+C` | `kubectl --context prod-0001 top nodes` |
| `:cpp` + `y` | `kubectl --context prod-guiyang-karmada get cpp <name> -o yaml` |
| `:ev` | `kubectl --context prod-0001 get events -A --sort-by=.lastTimestamp` |

> 复杂取证/留档建议用 kubectl（可重定向到文件）；快速人工巡检用 k9s。
