# codearts-workflow-image 工程分析报告

## 1. 概述

**项目名称：** codearts-workflow-image

**核心功能：** 将 CI/CD shell 脚本 + 环境变量自动转换为 **Volcano Job CRD**（Kubernetes 自定义资源）配置，并在华为 Ascend NPU 集群上执行。底层使用 Volcano 批量调度器替代了旧版的 Argo Workflows 引擎。

**技术栈：** Go 1.24, Kubernetes, Volcano, Karmada（多集群管理）

**转换流水线：** `shell.sh + env.sh + workflow_templatev2.yaml -> Go Converter -> workflow.yaml (Volcano Job CRD) + workflow-secret.yaml`

**目标平台：** 华为 Ascend NPU（910A, 910B1/B2/B3/B4, 310P3）、Karmada 多集群调度

---

## 2. 目录结构

```
codearts-workflow-image/
├── .ci/                    CI 流水线脚本
│   ├── typos.sh            拼写检查
│   ├── golangci-lint.sh    Go 代码检视
│   └── gosec.sh            Go 安全扫描
├── .opencode/              OpenCode 技能定义
│   └── skills/
│       ├── submit-test/     Volcano Job 测试提交
│       ├── diff-review/    提交前代码审查
│       ├── add-new-test-case/  添加测试用例指引
│       └── namespace-pvc-management/  命名空间/PVC 管理
├── configs/                Karmada 集群配置
│   ├── propagation-policies/  10 个传播策略
│   ├── queues/             3 个 Volcano 队列定义
│   ├── apply.sh            配置推送
│   ├── export.sh           配置导出
│   └── clean.sh            清理运行时字段
├── docs/                   文档
│   ├── ARCHITECTURE.md     架构全景（468 行）
│   ├── daily/              日常开发日志
│   ├── knowbase/           经验知识库
│   ├── mistakenotebook/    踩坑记录
│   ├── spec/               功能规格
│   └── superpowers/        设计规格与实施计划
├── go/                     Go 源码（主体）
│   ├── cmd/
│   │   ├── converter/      【核心】Shell 到 Volcano Job 转换器
│   │   ├── submit/         Volcano Job 提交与生命周期管理
│   │   ├── kubeconfig/     NPU 感知的 kubeconfig 选择器
│   │   ├── oldkubeconfig/  旧版 kubeconfig 查找
│   │   ├── envrender/      环境变量模板渲染（仅 debug 模式）
│   │   ├── ns/             仓库到命名空间映射
│   │   ├── parser/         简单 YAML 路径解析
│   │   └── common/         共用工具
│   └── test_convertv2_to_yaml.sh
├── scripts/                工具脚本
│   └── monitor-vcjob-restarts.sh  Volcano Job Pod 重启监控
├── src/                    容器入口脚本
│   ├── entrypoint.sh       主入口脚本
│   ├── select_kubeconfig.sh kubeconfig 选择
│   ├── unit.sh             测试单元运行器（旧版 Argo）
│   └── argo_cli_installer.sh Argo CLI 安装器
├── Dockerfile              容器镜像构建（多阶段）
├── docker_test.sh          基于 Docker 的集成测试
├── .golangci.yml           代码检视配置
├── typos.toml              拼写检查配置
├── AGENTS.md               AI Agent 操作指引
└── README.md 项目名称
```

---

## 3. 核心组件剖析

### 3.1 转换器（go/cmd/converter/）

转换器是整个工程的核心，位于 **go/cmd/converter/package/** 目录下，由多个职责单一的模块组成：

| 模块文件 | 行数 | 职责 |
|---------|------|------|
| `convert_script_to_volcano.go` | 311 | 主编排函数，组装整个 Volcano Job |
| `script_handler.go` | 65 | Git 克隆 + 脚本组装 |
| `script_handler_request.go` | 119 | Git/Artifact/DelayExit 脚本生成器 |
| `cp_config.go` | 97 | CP_* 环境变量提取（20+ 配置项） |
| `job_resource.go` | 139 | CPU/内存/NPU 资源计算 |
| `job_arch.go` | 36 | 架构 + NPU 芯片 NodeSelector |
| `affinity_manager.go` | 49 | NPU 亲和性（反亲和 310P3） |
| `queue_manager.go` | 38 | 队列选择（大任务/弹性） |
| `secret_filter.go` | 128 | 敏感变量检测与处理 |
| `secret_manager.go` | 59 | K8s Secret 清单生成 |
| `cp_artifact_manager.go` | 91 | Sidecar 容器 + 产物复制 |
| `dataset_manager.go` | 47 | 数据集 PVC 映射 |
| `image_proxy_manager.go` | 88 | 镜像代理（支持断网环境） |
| `shm_manager.go` | 26 | /dev/shm 共享内存卷 |
| `bandwidth_manager.go` | 19 | 入口带宽注解 |
| `custom_env.go` | 16 | 注入 MAX_JOBS 等自定义环境变量 |
| `post_label_manager.go` | 81 | 将 Pod 标签提升至 Job 层级 |
| `filter_name.go` | 60 | 名称合规化（Argo 兼容） |
| `action_render.go` | 215 | GitHub Actions YAML 渲染（实验性） |

#### 主函数 `ConvertScriptToVolcano()` 流程

```
1.  加载并解析 Volcano Job 模板 YAML
2.  确定队列（CPU >= 64 用 large-task-shared-queue，否则 shared-flexible-queue）
3.  设置 Volcano 标签（pipeline/run-id, jobPRID, jobRepositoryName）
4.  生成 Git 克隆脚本（带 CDN 缓存）
5.  生成产物复制脚本
6.  生成延迟退出的 trap 脚本
7.  设置容器镜像（含默认值与代理）
8.  设置 nodeSelector（架构 + NPU 芯片）
9.  添加 NPU 亲和性（通用 NPU 排除 310P3）
10. 计算资源（CPU/内存/NPU）
11. 添加 NPU 卷（ascend-driver hostPath）
12. 添加 SHM 卷（如设置 CP_shm）
13. 添加带宽注解（如设置 CP_bandwidth）
14. 设置 generateName（源自仓库 URL）
15. 处理环境变量（筛选敏感变量、解析引用、构建 Secret）
16. 添加数据集 PVC 卷
17. 设置 securityContext（runAsUser: 0）
18. 添加 copy-artifact sidecar 容器
19. 添加 NPU/PVC 标签
```

#### DTO 类型定义

**Volcano Job CRD（178 行）：** `Job, Metadata, JobSpec, Policy, Task, PodTemplate, PodSpec, Container, Resources, Volume, VolumeMount, EnvVar, Affinity, NodeSelector` 等完整类型。

**GitCode Actions（36 行）：** `Action, Input, Output, Runs, Step` 用于解析 GitHub Actions 格式 YAML。

### 3.2 CP_runs_on 解析器（go/cmd/common/run_on_parser.go）

解析格式：`<arch>-cpu-<N>-mem-<size>-<chip>-<npu_count>`

示例：`arm64-cpu-16-mem-32G-910b4-2`

- **架构支持：** amd64, arm64
- **NPU 芯片：** 910a, 910b1, 910b2, 910b3, 910b4, 310p3
- **NPU 资源映射：**
  - 910B 系列（ascend-1980）：1 NPU -> 12 CPU / 48Gi，上限 8 NPU
  - 310P3（ascend-310）：1 NPU -> 8 CPU / 16Gi，上限 8 NPU

### 3.3 提交器（go/cmd/submit/main.go, 1041行）

负责 Volcano Job 的提交、日志跟踪和生命周期管理：

1. **预提交验证**：Harbor 仓库可达性、Git 缓存检查、队列存在性、存储类、芯片、PVC
2. **Karmada 调度标签**：基于 PVC 和芯片位置添加 dispatch 标签
3. **kubectl create** 提交 Job
4. **Secret 注入**（带 ownerReference 自动清理）
5. **Pod 等待**：轮询发现主 Pod，检测镜像拉取失败
6. **日志流**：`kubectl logs -f`（带断线重连）
7. **产物提取**：`kubectl cp` 从 copy-artifact 容器复制

### 3.4 kubeconfig 选择器（go/cmd/kubeconfig/main.go）

- 收集所有 `.key` 文件中的 kubeconfig
- 查询每个集群可用 NPU 数
- **优先即时分配**，否则按最大可分配 NPU 加权随机选取
- 支持芯片过滤（仅匹配目标芯片类型的节点）

### 3.5 命名空间路由（go/cmd/common/namespace/）

按仓库名路由到不同命名空间：

| 仓库模式 | 命名空间 |
|---------|---------|
| `*ragsdk*`, `*ascend-text-embeddings-inference*` | `ragsdk` |
| `*ascend-op-plugin*`, `*ascend-pytorch*` | `op-plugin` |
| `*ascend-recsdk*` | `recsdk` |
| `*ascend-multimodalsdk*` | `multimodalsdk` |
| `*ascend-indexsdk*` | `indexsdk` |
| 默认 | `argo` |

---

## 4. 测试体系

### 4.1 测试框架

| 测试类型 | 命令 | 位置 |
|---------|------|------|
| 单元测试 | `go test -cover ./...` | 各包 `_test.go` |
| E2E 测试 | `go test -v -run Test_main` | `convertv2_to_yaml_test.go` |
| Volcano Job 测试 | `skill submit-test -k <kubeconfig> -t all` | `.opencode/skills/submit-test/` |

### 4.2 测试用例（38 个）

每个用例包含：`env.sh`（CP_* 变量）、`shell.sh`（脚本）、`expected.yaml`（期望输出）、`eval.sh`（部署后验证）

| 编号 | 测试用例 | 测试场景 |
|------|---------|---------|
| test1 | simple | 基础 ARM64 脚本执行，默认资源 |
| test2 | with-secrets | 敏感变量环境变量 |
| test3 | custom-resources | 自定义 CPU (16) + 内存 (32Gi) |
| test4 | custom-image | 自定义 Docker 镜像 |
| test5 | no-merge-id | 无合并 ID 的 Git 克隆 |
| test6 | empty-sensitive-value | 空敏感值过滤 |
| test7 | workspace-filtered | WORKSPACE 变量过滤 |
| test8 | git-clone | GitCode 仓库克隆 |
| test9 | 910b4 | NPU 910B4（12 CPU/48Gi） |
| test10 | cp-artifacts | 产物复制到 /output |
| test11 | git-clone-var-ref | 变量引用解析 |
| test12 | normal-workflow | 自定义工作流模板 |
| test13 | cp-artifacts-v2 | 产物复制 v2 |
| test14 | exit1 | 失败时延迟退出 |
| test15 | dataset | 数据集 PVC 挂载 |
| test16 | dataset-mapping | 数据集 PVC 名称映射 |
| test17 | image-pull-failure | 镜像拉取策略测试 |
| test18 | with-secrets | Secret 清单生成 |
| test19 | dynamic-timestamp | 动态时间戳 |
| test20 | ascend-driver | Ascend NPU 驱动挂载 |
| test21 | dataset | 数据集映射 |
| test22 | git-cdn | Git CDN 代理配置 |
| test23 | large-queue | 大任务队列选择 |
| test24 | image-proxy | 镜像代理 |
| test25 | shm | 共享内存卷 /dev/shm |
| test26 | npu-generic | 通用 NPU（反亲和 310P3） |
| test27 | 310p3 | 310P3 芯片 |
| test28 | gz-dataset | 广州数据集 |
| test29 | cp-artifact-failure | 失败时产物复制 |
| test30 | cp-pull-failure | 产物拉取失败 |
| test31 | git-clone-cp-artifacts | Git 克隆 + 产物组合 |
| test32 | no-artifact-files | 空产物文件 |
| test33 | goproxy | Go 代理配置 |
| test34 | ipv6 | IPv6 网络 |
| test35 | ingress-bandwidth | 入口带宽注解 |
| test36 | image-pull-policy | 自定义拉取策略 |
| test37 | delay-exit | 自定义延迟退出 (20s) |
| test38 | dataset-readonly | 只读数据集挂载 |

---

## 5. CP_* 环境变量参考

| 变量 | 类型 | 说明 | 默认值 |
|------|------|------|--------|
| `CP_runs_on` | string | 运行目标规格（arch-cpu-mem-chip-npu） | `arm64-cpu-8-mem-8G` |
| `CP_docker_image` | string | 容器镜像 | `gosrc.io/ci-worker:latest` |
| `CP_timeout` | int | 超时秒数 | 14400（4小时） |
| `CP_pipeline_run_id` | string | 流水线运行 ID | - |
| `CP_merge_id` | string | 合并请求 ID | - |
| `CP_repo_url` | string | 仓库 URL | - |
| `CP_target_branch` | string | 目标分支 | - |
| `CP_artifacts` | string | 产物文件模式 | - |
| `CP_artifacts_temp_folder` | string | 产物临时目录 | `/output` |
| `CP_dataset` | string | 数据集路径（支持 /path 或 /path,readonly） | - |
| `CP_image_proxy` | string | 镜像代理 URL | `harbor-portal.osinfra.cn` |
| `CP_shm` | string | 共享内存大小 | - |
| `CP_bandwidth` | string | 入口带宽 | 150M |
| `CP_image_pull_policy` | string | 拉取策略 | `IfNotPresent` |
| `CP_delay_exit` | int | 非零退出延迟秒数 | 10 |

---

## 6. Git CDN 缓存机制

转换器自动为 5 个 Git 提供商生成 CDN 代理配置：

| 提供商 | 缓存 URL |
|--------|---------|
| gitcode.com | `https://gitcode-cache.osinfra.cn` |
| github.com | `https://github-cache.osinfra.cn` |
| gitee.com | `https://gitee-cache.osinfra.cn` |
| atomgit.com | `https://atomgit-cache.osinfra.cn` |
| codehub.devcloud.huaweicloud.com | `https://codehub-cache.osinfra.cn` |

通过 `git config --global url."<cache>".insteadOf <origin>` 实现透明代理。

---

## 7. Karmada 传播策略

配置 10 个 Karmada 传播策略，实现多集群调度：

| 策略 | 类型 | 目标集群 | 用途 |
|------|------|---------|------|
| `argo-policy` | PropagationPolicy | All | Volcano Jobs + batch Jobs（argo 命名空间） |
| `pod-member1-policy` | PropagationPolicy | member1 | Pod 调度到 member1 |
| `pod-member2-policy` | PropagationPolicy | member2 | Pod 调度到 member2 |
| `secret-member1-policy` | PropagationPolicy | member1 | Secret 分发 |
| `secret-member2-policy` | PropagationPolicy | member2 | Secret 分发 |
| `ragsdk-policy` | PropagationPolicy | member2 | ragsdk 命名空间调度 |
| `default-volcano-global-dispatch-policy` | PropagationPolicy | All | 全局 Volcano Job 分发 |
| `cluster-argo-namespace-propagation` | ClusterPropagationPolicy | member1, member2 | argo 命名空间分发 |
| `cluster-volcano-global-all-queue-propagation` | ClusterPropagationPolicy | All | Volcano 队列分发 |
| `cluster-ragsdk-namespace-propagation` | ClusterPropagationPolicy | member1, member2 | ragsdk 命名空间分发 |

---

## 8. 队列设计

| 队列 | 权重 | 容量 | 用途 |
|------|------|------|------|
| `default` | 1 | - | 默认队列 |
| `shared-flexible-queue` | - | - | 弹性共享队列 |
| `large-task-shared-queue` | - | 196 CPU / 1500Gi 内存，优先级 100 | 大任务队列（CPU >= 64） |

---

## 9. 容器镜像构建

**Dockerfile（多阶段构建）：**

1. **Stage 1（go-builder）：** `golang:1.24-alpine`，编译 `convert_to_yaml`, `kubeconfig`, `submit` 三个二进制
2. **Stage 2（runtime）：** `alpine:3.18`，安装 git, bash, curl, gzip, jq, kubectl

**最终镜像：**
- 二进制路径：`/workspace/workflowtool/`
- 入口点：`/bin/bash`（由 entrypoint.sh 驱动）
- 默认镜像拉取凭据：`huawei-swr-image-pull-secret-model-gy`
- 默认工作目录：`/workspace`

---

## 10. CI 流水线

| 步骤 | 脚本 | 功能 |
|------|------|------|
| 拼写检查 | `.ci/typos.sh` | typos-cli 拼写检查（排除 yaml/json/toml/md） |
| 代码检视 | `.ci/golangci-lint.sh` | golangci-lint（12 个 linter） |
| 安全扫描 | `.ci/gosec.sh` | Docker 镜像 gosec 扫描 |

---

## 11. 架构全景

```
输入
├── shell.sh     (用户 CI/CD 脚本)
├── env.sh       (CP_* 配置 + 用户环境变量)
└── workflow_templatev2.yaml (Volcano Job 模板)
  │
  ▼
转换器 (convert_to_yaml)
├── GetCPConfig() → 提取 CP_* 变量
└── ConvertScriptToVolcano() → 组装 Volcano Job
    ├── 生成 Git 克隆脚本（带 CDN 缓存）
    ├── 生成延迟退出 trap
    ├── 生成产物复制脚本
    ├── 计算资源（CPU/内存/NPU）
    ├── 设置 NodeSelector + NPU 亲和性
    ├── 处理环境变量（筛选敏感/解析引用）
    ├── 构建卷（dataset, ascend-driver, shm）
    └── 添加 Sidecar + 标签 + 注解
  │
  ▼
输出
├── workflow.yaml          (Volcano Job CRD)
└── workflow-secret.yaml   (K8s Secret，可选)
  │
  ▼
提交器 (submit)
├── 预提交验证（Harbor/Git/队列/芯片/PVC）
├── 添加 Karmada 调度标签
├── kubectl create + Secret 注入
├── 等待 Pod + 日志流
├── 检测镜像拉取失败
├── 产物提取 (kubectl cp)
└── 清理
```

---

## 12. 关键设计决策

1. **TDD 驱动开发**：每个功能都有对应的 E2E 测试用例（38 个），并通过 `expected.yaml` 验证输出
2. **敏感变量延迟判定**：`sensitivePatterns` 列表当前为空（所有值已注释），实际由 env.sh 决定哪些变量写入 Secret
3. **Karmada 多集群**：通过 `dispatch/<cluster>=true` 标签实现跨集群工作负载调度
4. **NPU 反亲和**：通用 NPU 自动排除 310P3 节点，确保 910B 系列 NPU 不被误调度
5. **延迟退出机制**：非零退出时 sleep N 秒，提供调试窗口

---

## 13. AGENTS.md 要点（AI Agent 操作注意事项）

> **修改代码前务必先阅读 `docs/mistakenotebook/`，避免重蹈历史错误。**

- 测试命令：`go test -cover ./...`（单元）、`go test -v -run Test_main`（E2E）
- CI：typos → golangci-lint → gosec
- 新增功能时在 `case/newtest/` 中添加测试用例
- 路径覆盖率要求 > 90%
