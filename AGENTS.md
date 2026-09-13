# Global Codex Workflow Rules

- Use `<USER_HOME>\.codex\WORKFLOW_ROUTER.md` as the human-readable routing constitution and `<USER_HOME>\.codex\ROUTING_CATALOG.json` as the single machine-readable routing source of truth.
- Classify `intent`, one or more `domains`, `scale`, `risk`, and required capabilities before execution. Use the smallest sufficient capability set: zero or one Primary Skill, zero to four Supporting Skills, mapped Providers only, and explicit Verification.
- Use `<USER_HOME>\.codex\CAPABILITIES_SUMMARY.json` for default capability discovery. Read Full Index details only when the routed task needs them. Do not treat installed, cached, configured, discoverable, runtime-available, connected, or healthy as interchangeable states.
- FAST is for small isolated work; STANDARD is for ordinary work; DEEP is for large, cross-module, high-risk, long-running, or independently parallelizable work. DEEP does not automatically create a Worktree or Subagent.
- Before claiming non-trivial work is complete, run fresh verification and report actual evidence, including `SKIPPED`, `NOT_TESTED`, or `UNAVAILABLE` boundaries. Keep deterministic tests separate from Real Agent Eval; never fabricate a live-agent result.
- When the user asks `Explain routing decision`, output the computed `ROUTING_DECISION` block and the evidence used for intent, domains, scale, risk, roles, providers, Worktree, Subagents, and Verification.
- Preserve existing MCP configuration, Hooks, Automations, Plugin cache, Skills, credentials, Worktrees, projects, and Obsidian behavior unless the user explicitly authorizes a scoped change. Create a timestamped backup before changing global Router artifacts.

## Skill mirror rule

- When installing a Codex Skill for this user, also copy that Skill's `SKILL.md` into the appropriate category subfolder under `<USER_HOME>\Documents\Obsidian Vault\ai有关的装备\skills`, named `<skill-name>.md`.
- Do not place new Skill markdown files directly in the `skills` root unless the user explicitly asks for that exact location.
- Use the installed Codex Skill file as the source of truth, normally `<USER_HOME>\.codex\skills\<skill-name>\SKILL.md`; choose the category from the existing folder taxonomy and verify the copied Obsidian file matches the source.

## References

- Human routing constitution: `<USER_HOME>\.codex\WORKFLOW_ROUTER.md`
- Machine routing catalog: `<USER_HOME>\.codex\ROUTING_CATALOG.json`
- Default capability index: `<USER_HOME>\.codex\CAPABILITIES_SUMMARY.json`
- Complete capability index: `<USER_HOME>\.codex\CAPABILITIES_FULL.json`

