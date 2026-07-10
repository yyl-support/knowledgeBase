# k9s 多集群使用指南

本环境已将「正式」与「测试」两套集群的 kubeconfig 合并到 `~/.kube/config`，
所有集群的 context / cluster / user 名称都做了唯一化重命名，避免冲突。
k9s 与 kubectl 默认读取该文件，开箱即用。

---

## 一、可用的集群 (Context)

| 环境  | Context 名称                            | 说明 / API Server                   |
| --- | ------------------------------------- | --------------------------------- |
| 正式  | `prod-0001`                           | 101.245.109.198:5443              |
| 正式  | `prod-guiyang-ipv6-internal`          | 贵阳 内网 10.0.1.27:5443              |
| 正式  | `prod-guiyang-ipv6-external`          | 贵阳 外网 1.95.170.83:5443            |
| 正式  | `prod-guiyang-ipv6-externalTLSVerify` | 贵阳 外网(校验TLS) 1.95.170.83:5443     |
| 正式  | `prod-wlcb`                           | 1.92.221.43:5443                  |
| 正式  | `prod-guiyang-karmada`                | 贵阳 Karmada 1.95.223.182:5443      |
| 正式  | `prod-guiyang-karmada-deploy`         | 贵阳 Karmada 部署集群 122.9.143.91:5443 |
| 测试  | `test-006`                            | 1.95.209.90:5443                  |
| 测试  | `test-007`                            | 1.95.6.19:5443                    |
| 测试  | `test-karmada`                        | 测试 Karmada 1.95.134.239:5443      |
| 测试  | `test-karmada-proxy`                  | 测试 Karmada Proxy 聚合接口             |

> 命名规则：`环境-来源[-子上下文]`。`prod-` 为正式，`test-` 为测试。

---

## 二、k9s 使用

### 1. 启动

```bash
k9s
```

默认进入当前 context（`prod-0001`）。

### 2. 切换集群

在 k9s 界面里输入命令（按 `:` 会进入命令模式）：

```
:ctx          # 列出所有 context，回车选择要切换的集群
:context      # 同上（完整写法）
```

也可以启动时直接指定集群：

```bash
k9s --context test-006
k9s --context prod-guiyang-karmada
```

### 3. 常用界面操作

| 按键 / 命令 | 作用 |
|-------------|------|
| `:ns`        | 切换 / 查看命名空间 |
| `:pod`       | 查看 Pod 列表 |
| `:svc`       | 查看 Service |
| `:deploy`    | 查看 Deployment |
| `:node`      | 查看节点 |
| `/关键字`    | 在当前列表中过滤 |
| `l`          | 查看日志（选中 Pod 后） |
| `d`          | describe 资源 |
| `s`          | 进入 shell（选中 Pod 后） |
| `Esc`        | 返回上一级 |
| `:q` / `Ctrl+C` | 退出 k9s |

### 4. 指定命名空间启动

```bash
k9s --context prod-0001 -n argo
```

---

## 三、kubectl 使用（等价校验）

### 查看所有 context

```bash
kubectl config get-contexts
```

### 切换默认 context

```bash
kubectl config use-context test-006
```

### 临时指定 context 执行命令（不改默认值）

```bash
kubectl --context prod-guiyang-karmada get ns
kubectl --context test-006 get pods -n argo
```

### 查看当前 context

```bash
kubectl config current-context
```

---

## 四、配置文件位置

| 文件 | 路径 |
|------|------|
| 合并后的 kubeconfig | `~/.kube/config` |
| k9s 配置 | `~/.config/k9s/config.yml` |
| k9s 日志 | `/tmp/k9s-root.log` |

原始 kubeconfig 仍保留在：

- 正式：`/root/yyl/cluster/正式/`
- 测试：`/root/yyl/cluster/测试/`

---

## 五、常见问题

- **连不上某集群**：多为网络不通或该 API Server 不在当前网络可达范围，先用
  `kubectl --context <名称> get ns` 验证。
- **想新增集群**：把新的 kubeconfig 放入对应目录，重新执行合并脚本
  `python3 /tmp/opencode/merge_kubeconfig.py` 即可（会重建 `~/.kube/config`）。
- **恢复干净状态**：删除 `~/.kube/config` 后重新运行合并脚本。
