#!/bin/bash
set -e

echo "=== Stage 4: 打包发布 ==="

# 产出目录
mkdir -p package

# 打包模型
if [ -f /output/model_final.pt ]; then
    cp /output/model_final.pt package/
    echo "模型已打包: package/model_final.pt"
else
    echo "错误: 找不到模型文件"
    exit 1
fi

# 生成版本信息
echo "version: $(date +%Y%m%d-%H%M%S)" > package/VERSION
echo "model: model_final.pt"          >> package/VERSION

tar -czf package.tar.gz package/
echo "发布包: package.tar.gz ($(du -h package.tar.gz | cut -f1))"
