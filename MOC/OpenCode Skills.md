---
tags:
  - MOC
  - skills
  - opencode
  - AI-Agent
---

# 🤖 OpenCode Skills

> OpenCode / Claude Code 内置技能库（`~/.config/opencode/skills/`），共 19 个技能，通过 symlink 接入本库。每个技能提供一个 `SKILL.md` 入口文件，部分技能附带 reference 文档。

## 📄 文档与文件

- [[skills/docx/SKILL|docx]] — Word 文档 (.docx) 的创建、读写与编辑
- [[skills/pdf/SKILL|pdf]] — PDF 文件处理（合并 / 拆分 / 提取 / OCR）
- [[skills/pptx/SKILL|pptx]] — 演示文稿 (.pptx) 的创建与编辑
- [[skills/xlsx/SKILL|xlsx]] — 电子表格 (.xlsx/.csv) 的数据与公式处理

## 🎨 设计与视觉

- [[skills/frontend-design/SKILL|frontend-design]] — 生产级前端界面设计（React / Tailwind）
- [[skills/web-artifacts-builder/SKILL|web-artifacts-builder]] — 复杂多组件 HTML 制件构建
- [[skills/webapp-testing/SKILL|webapp-testing]] — Playwright Web 应用测试
- [[skills/algorithmic-art/SKILL|algorithmic-art]] — p5.js 生成艺术 / 粒子系统
- [[skills/canvas-design/SKILL|canvas-design]] — .png / .pdf 静态视觉设计
- [[skills/brand-guidelines/SKILL|brand-guidelines]] — Anthropic 品牌色与字体
- [[skills/slack-gif-creator/SKILL|slack-gif-creator]] — Slack 优化的动画 GIF 制作
- [[skills/theme-factory/SKILL|theme-factory]] — 10 套预设主题（色板 + 字体）

## 🧠 AI 与 API

- [[skills/claude-api/SKILL|claude-api]] — Claude API / Anthropic SDK 全栈参考（模型 / 价格 / 流式 / 工具 / MCP）
- [[skills/mcp-builder/SKILL|mcp-builder]] — MCP Server 开发指南（Python FastMCP / TypeScript SDK）

## 🔧 工程与运营

- [[skills/github-aiflow-analysis/SKILL|github-aiflow-analysis]] — backlog AI Flow CI 日志诊断工具（与本库 AI Flow 体系联动）
- [[skills/github-ops/SKILL|github-ops]] — GitHub REST API 底层操作封装
- [[skills/skill-creator/SKILL|skill-creator]] — 技能的创建、修改与性能评估
- [[skills/internal-comms/SKILL|internal-comms]] — 企业内部通讯（状态报告 / 新闻稿 / 事故报告）

## ✍️ 写作与协作

- [[skills/doc-coauthoring/SKILL|doc-coauthoring]] — 文档协同写作的结构化工作流

---

## 🔗 与本库的关联

| OpenCode Skill | 本库相关 MOC / 笔记 |
|---------------|-------------------|
| github-aiflow-analysis | [[ai-flow 体系]] · [[错误库]] · [[backlog-CI-术语解释]] |
| github-ops | 开源组织代码分析相关 |
| claude-api | LLM 能力相关的通用知识 |
| skill-creator | Skills 体系的自我迭代 |

> symlink 路径: `skills/ → ~/.config/opencode/skills/`。技能的修改会直接反映到 OpenCode 运行时。

---

> 返回 [[首页]]
