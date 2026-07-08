# ============================================
# Stage 3: 模型训练 — 2颗昇腾 910B4 NPU
# ============================================

# 资源配置：ARM64，12核CPU，48G内存，2颗 Ascend 910B4
export CP_runs_on="arm64-cpu-12-mem-48G-910b4-2"

# 训练镜像（含 PyTorch + torch-npu）
export CP_docker_image="swr.cn-north-4.myhuaweicloud.com/ai/pytorch-ascend:v2.1"

# 挂载预训练权重 — 只读
export CP_dataset="/dataset/model-weights,readonly"

# 共享内存 32G（多卡训练 NCCL 需要）
export CP_shm="32G"

# 延迟退出 60 秒（出错了给时间登录容器排查）
export CP_delay_exit="60"

# 超时 4 小时
export CP_timeout="14400"
