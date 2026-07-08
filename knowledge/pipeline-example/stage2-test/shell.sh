#!/bin/bash
set -e

echo "=== Stage 2: 单元测试 ==="

cd build
ctest --output-on-failure -j$(nproc)

echo "测试全部通过"
