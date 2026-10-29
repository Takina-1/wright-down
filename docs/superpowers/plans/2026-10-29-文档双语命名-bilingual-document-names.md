# 文档双语命名实施计划 / Bilingual Document Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将项目 Markdown 文档统一为中文主题与英文主题组合的文件名，并保持所有入口和链接有效。

**Architecture:** 固定入口保留 `README.md`、`AGENTS.md`、`CLAUDE.md`；其余文档采用 `<中文主题>-<english-topic>.md`，功能文档保留最前面的 `F编号-`，计划、报告、模板等类型同时体现在中英文部分。目录结构保持不变。

**Tech Stack:** Markdown、PowerShell、Git。

**Spec:** 用户要求“文档名称需要中英文名结合，所有的都是，可写入 agent.md 和 claude.md”。

## Global Constraints

- 更新所有相对链接、索引和正文中的路径示例。
- 保留现有文档内容和功能编号。
- 固定入口文件名不改，避免工具失去约定入口。

## Review Focus

- 不得留下指向旧文件名的本地链接。
- 新增文档也必须遵守双语文件名规则。
- `AGENTS.md` 与 `CLAUDE.md` 的规则必须一致。
- 模板中的路径示例必须同步更新。
- Git 应识别为重命名或等价内容迁移，不得丢失文档。

---

### Task 1: 写入命名约定

**Files:**
- Modify: `AGENTS.md`
- Create: `CLAUDE.md`
- Modify: `docs/开发流程-development-workflow.md`

- [x] 明确双语文件名格式与固定入口例外。
- [x] 更新开发流程中的命名表和示例。

### Task 2: 批量重命名文档

**Files:**
- Rename: `docs/` 下除固定入口外的现有 Markdown 文档。

- [x] 按映射移动项目级、功能、测试报告和模板文档。
- [x] 保持目录结构和功能编号不变。

### Task 3: 修复链接并验证

**Files:**
- Modify: repository Markdown files containing old paths.

- [x] 更新所有索引、相对链接和路径示例。
- [x] 使用 `rg` 确认旧文件名不再被引用。
- [x] 使用 `git diff --check` 检查文档改动。
