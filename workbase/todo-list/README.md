---
tags:
  - workbase
  - todo-list
---

# todo-list 使用说明与 day-planner 接入

> 每日工作项目录，按 `年/月` 归类，例如 `todo-list/2026/07/2026-07-08.md`。

## Day Planner 接入（已配置）

- **Day Planner 插件**：已安装并启用（`.obsidian/plugins/obsidian-day-planner`，v0.31.0，作者 ivan-lednev，仓库 https://github.com/ivan-lednev/obsidian-day-planner）。
- **每日笔记位置**：已在核心「Daily Notes」插件中配置（`.obsidian/daily-notes.json`）——
  - 文件夹（New file location）：`workbase/todo-list`
  - 日期格式（Date format）：`YYYY/MM/YYYY-MM-DD`
  - 即今日的每日笔记会落在 `workbase/todo-list/2026/07/2026-07-08.md`。
- Day Planner 直接读取上述 Daily Notes 设置，无需在插件内重复配置文件夹。

在当日 todo 文件中用如下格式记录，可自动生成时间轴并关联日历：

```markdown
- 09:00 - 09:30 晨会
- 09:30 - 12:00 处理 issue-921 联调
- 14:00 - 15:00 文档整理
```

## 每日模板

模板文件：`workbase/templates/daily-todo.md`（由 Templater 处理）。当日笔记分三部分：

- **月度任务**：本月目标，跨天沿用。存于 `todo-list/年/月/年-月.md`（如 `2026/07/2026-07.md`）。
- **周度任务**：本周目标，跨天沿用。存于 `todo-list/年/月/年-Www.md`（ISO 周号，如 `2026/07/2026-W28.md`）。
- **当日任务**：含 day-planner 计划时间轴与今日事项，每天独立。

## 月度/周度任务同步（Templater + 嵌入引用）

月度、周度任务**不写进每天的文件**，而是各自单独一个文件，当日笔记通过嵌入引用它们，改一次全局同步：

```markdown
## 月度任务
![[2026-07#月度任务]]

## 周度任务
![[2026-W28#周度任务]]
```

- **Templater 插件**：已安装并启用（`.obsidian/plugins/templater-obsidian`），配置见其 `data.json`：
  - 模板文件夹：`workbase/templates`
  - 已开启「Trigger Templater on new file creation」
  - 文件夹模板：`workbase/todo-list` → `workbase/templates/daily-todo.md`
- 因此在 `workbase/todo-list` 下由 Daily Notes 新建当天笔记时，Templater 会自动用当前日期生成正确的月/周引用（`YYYY-MM`、`GGGG-[W]WW`），**新建一天无需手动改任何日期**。
- 引用用 wikilink 基础名解析，与文件所在子目录无关，只要文件名唯一即可。

### 每月/每周初始化

- **新的一月**：复制 `2026-07.md` 为 `年/月/年-月.md` 并清空任务。
- **新的一周**：复制 `2026-W28.md` 为 `年/月/年-Www.md`（ISO 周号，可在日历或 `date` 命令查）并清空任务。
- ⚠️ 这两类文件请用**复制**方式创建，不要在 Obsidian 里从零新建于 `todo-list` 内——否则会被文件夹模板当成当日笔记填充。
