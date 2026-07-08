---
tags:
  - workbase
  - todo-list
---

# todo-list 使用说明与 day-planner 接入

> 每日工作项目录，按 `年/月/日` 归类，例如 `todo-list/2026/07/08/2026-07-08.md`。

## Day Planner 接入（已配置）

- **Day Planner 插件**：已安装并启用（`.obsidian/plugins/obsidian-day-planner`，v0.31.0，作者 ivan-lednev，仓库 https://github.com/ivan-lednev/obsidian-day-planner）。
- **每日笔记位置**：已在核心「Daily Notes」插件中配置（`.obsidian/daily-notes.json`）——
  - 文件夹（New file location）：`workbase/todo-list`
  - 日期格式（Date format）：`YYYY/MM/DD/YYYY-MM-DD`
  - 即今日的每日笔记会落在 `workbase/todo-list/2026/07/08/2026-07-08.md`。
- Day Planner 直接读取上述 Daily Notes 设置，无需在插件内重复配置文件夹。

在当日 todo 文件中用如下格式记录，可自动生成时间轴并关联日历：

```markdown
- 09:00 - 09:30 晨会
- 09:30 - 12:00 处理 issue-921 联调
- 14:00 - 15:00 文档整理
```

## 每日模板

见同目录（或当日目录）下的 `2026-07-08.md`，可复制为新一天的起点。
