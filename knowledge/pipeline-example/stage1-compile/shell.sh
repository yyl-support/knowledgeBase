#!/bin/bash
set -e

echo "=== Stage 1: 编译 ==="
echo "架构: $(uname -m)"
echo "CPU 核数: $(nproc)"

# 项目根目录在 /workspace（git clone 后自动进入）
mkdir -p build && cd build

cmake .. -DCMAKE_BUILD_TYPE=Release -DUSE_ASCEND=ON
make -j$(nproc)

echo "编译完成，产物:"
ls -lh *.so *.o 2>/dev/null || echo "无 .so/.o 文件"

# CP_artifacts 会自动把 build/*.so 和 build/*.o 复制到 /output
