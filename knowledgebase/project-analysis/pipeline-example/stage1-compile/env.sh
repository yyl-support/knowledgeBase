# ============================================
# Stage 1: 编译 — 纯 CPU，通用计算集群
# ============================================

# 资源配置：AMD64，8核CPU，16G内存，无 NPU
export CP_runs_on="amd64-cpu-8-mem-16G"

# 编译用的基础镜像（含 gcc/cmake）
export CP_docker_image="swr.cn-north-4.myhuaweicloud.com/ci/compile-tools:v2.3"

# 超时 30 分钟
export CP_timeout="1800"

# 产物：编译结果输出到 /output
export CP_artifacts="build/*.so build/*.o"
export CP_artifacts_temp_folder="/output"
