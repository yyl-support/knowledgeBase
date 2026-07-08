---
tags:
  - workbase
  - todo-list
---

# todo-list 使用说明与 day-planner 接入

> 每日工作项目录，按 `年/月/日` 归类，例如 `todo-list/2026/07/08/2026-07-08.md`。

## 接入 Day Planner 插件（可选）

1. Obsidian → 设置 → 第三方插件 → 关闭安全模式 → 浏览，搜索 **Day Planner**（作者 ivan-lednev，仓库 https://github.com/ivan-lednev/obsidian-day-planner），安装并启用。
2. 在插件设置里将「每日笔记 / Planner 文件夹」指向 `workbase/todo-list`，日期格式设为 `YYYY/MM/DD`。
3. 在当日 todo 文件中用如下格式记录，可自动生成时间轴并关联日历：

```markdown
- 09:00 - 09:30 晨会
- 09:30 - 12:00 处理 issue-921 联调
- 14:00 - 15:00 文档整理
```

## 每日模板

见同目录（或当日目录）下的 `2026-07-08.md`，可复制为新一天的起点。
