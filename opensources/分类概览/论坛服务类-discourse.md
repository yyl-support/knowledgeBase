---
tags:
  - 服务
  - discourse
  - 论坛类
---

# 论坛服务类 — Discourse

> 代表性仓库：`opensourceways/discourse`（fork）
> 分析来源：GitHub README 公开内容

## 仓库定位

Discourse 是开源社区论坛平台，已运行十余年，是 `opensourceways` 组织所服务的 openEuler 社区的前台论坛底座。该仓库是对上游 `discourse/discourse` 的 fork，openEuler 社区在此基础上进行定制化。

## 核心能力

- **讨论话题**：创建和管理讨论主题
- **实时聊天**：内置聊天功能
- **主题定制**：官方和社区主题生态
- **插件扩展**：支持 AI 聊天机器人（Discourse AI）、数据分析（Data Explorer）等插件
- **自托管**：完全自控的基础设施部署

## 组织内的相关仓库

| 仓库 | 用途 |
|------|------|
| `discourse` | 论坛核心代码（fork） |
| `discourse_docker` | Docker 化部署方案（fork） |
| `discourse-color-scheme-toggle` | 主题切换插件（fork） |
| `discourse-formatting-toolbar` | 格式化工具栏插件（fork） |
| `discourse-fully` | 全宽布局主题（fork） |
| `discourse-oauth2-basic` | OAuth2 登录插件（fork，已归档） |
| `discourse-multilingual` | 多语言支持插件（fork，已归档） |
| `header-locale-selector` | 语言切换组件（fork） |

## 与机器人的关系

`forum-reply-robot` 通过 Discourse API 拉取论坛帖子、分类过滤、自动回帖，是论坛的自动化增强层。

---

## 🔗 相关笔记

- [[issue-921-helm改动对比分析]] — discourse chart 中部署 robot
- [[issue-921-RAG对外域名全链路]] — discourse 域名分流
- [[README]] — 组织总览

> 索引：[[服务总览]] · 返回 [[首页]]
