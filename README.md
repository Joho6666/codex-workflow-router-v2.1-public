# Codex Workflow Router v2.1

这是当前 Codex 配置项目的公开安全快照，重点是 Workflow Router v2.1 P0 可靠性闭环：路由目录、能力索引、Runtime/MCP 证据、测试、真实隔离 Agent Eval 和验收报告。

## 当前状态

- MCP 配置源只包含 `node_repl` 和 `chatcut_desktop`。
- PowerShell 7 自测：183 PASS、0 FAIL、0 SKIP。
- Parser failures：0。
- Real Agent Eval：8/8 PASS。
- Runtime 健康状态保持未知时，报告明确输出 `READY_FOR_ADAPTIVE_ROUTER: NO`。

## 公开安全边界

`config.toml.example` 保留当前配置结构和能力定义，但已将 bearer token、机器路径、用户目录、运行时路径和本机项目信任条目替换为占位符。请复制为本地 `config.toml` 后再填写本机值；不要将真实 `config.toml`、`auth.json` 或 `.env` 提交到公开仓库。

本仓库不包含 Codex auth、session、日志、数据库、cache、插件 cache、attachments、secrets、worktree 或 Obsidian 内容。

## 目录说明

- `WORKFLOW_ROUTER.md`：人类可读的路由宪法。
- `ROUTING_CATALOG.json`：机器可读的唯一路由来源。
- `CAPABILITIES_SUMMARY.json` / `CAPABILITIES_FULL.json`：能力索引。
- `MCP_RUNTIME_STATUS.json` / `RUNTIME_TOOLS.json`：运行时证据快照。
- `scripts/`：Router、索引、测试和报告脚本。
- `WORKFLOW_ROUTER_V2_1_REPORT.md`：最终验收报告。

## 关键 P0 规则

- `task_types` 仅保留兼容和报告用途，不参与实际评分。
- 稳定去重保留首次出现顺序。
- 单模块并行任务不会自动启用 Worktree/Subagent。
- 三个独立低冲突模块同时满足条件时才启用 Worktree/Subagent。
- Next.js/Vercel 部署没有明确 Deployment Primary 时不选择 `frontend-design`。
- Mirasim-only Skill 只进入 External/Unknown 审计区，不进入严格 Codex 执行链。


