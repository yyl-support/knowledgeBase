# ============================================
# Stage 4: 打包发布 — 纯 CPU
# ============================================

# 资源配置：AMD64，4核CPU，8G内存，无 NPU
export CP_runs_on="amd64-cpu-4-mem-8G"

export CP_docker_image="swr.cn-north-4.myhuaweicloud.com/ci/pack-tools:v1.0"

export CP_timeout="300"
