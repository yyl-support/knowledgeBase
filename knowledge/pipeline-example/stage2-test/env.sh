# ============================================
# Stage 2: 单元测试 — 纯 CPU，通用计算集群
# ============================================

# 资源配置：AMD64，4核CPU，8G内存，无 NPU
export CP_runs_on="amd64-cpu-4-mem-8G"

# 测试镜像
export CP_docker_image="swr.cn-north-4.myhuaweicloud.com/ci/test-runner:v1.0"

export CP_timeout="600"
