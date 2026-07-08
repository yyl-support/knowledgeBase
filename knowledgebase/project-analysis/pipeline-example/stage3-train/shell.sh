#!/bin/bash
set -e

echo "=== Stage 3: 模型训练 ==="

# 检查 NPU 是否可见
npu-smi info 2>/dev/null && echo "NPU 检测成功" || echo "警告: npu-smi 不可用"
echo "可用 NPU 数量: $(npu-smi info -l 2>/dev/null | grep -c 'Chip')"

# 从上一个 Stage 的产物中加载编译好的 .so
# （由 Pipeline 平台在 Stage 间传递，这里假设已在 /workspace/build/）
if [ -f build/libmodel.so ]; then
    echo "已加载编译产物: build/libmodel.so"
else
    echo "编译产物不存在，将使用预编译版本"
fi

# 预训练权重从 PVC 挂载，路径 /dataset/model-weights/
ls -lh /dataset/model-weights/ 2>/dev/null || echo "权重文件未挂载"

# 启动多卡训练
# torchrun 会根据 NPU 数量自动分配进程
torchrun --nproc_per_node=2 train.py \
    --epochs 100 \
    --batch-size 64 \
    --pretrained /dataset/model-weights/checkpoint_latest.pt \
    --output /output/model_final.pt

echo "训练完成，模型已保存到 /output/model_final.pt"
