# 0001 — Keep a bespoke generator rather than adopting AgentSync or ai-rules-sync

Status: accepted · 2026-08-26

## Context

`tools/generate.ps1` fans one canonical standard out to Claude Code
(`.claude/rules/*.md`, `paths:` YAML list) and GitHub Copilot
(`.github/instructions/*.instructions.md`, `applyTo:` comma string). It was written
without checking prior art. A reality check found the problem is largely solved.

| | Path-scoped fan-out | Shared source outside the repo | Dead-glob validation |
|---|---|---|---|
| [AgentSync](https://github.com/yelmuratoff/agent_sync) | yes — same two conversions, 13 tools | **no** — source is always `.ai/src/` in the repo | no |
| [ai-rules-sync](https://github.com/lbb00/ai-rules-sync) | **no** — no scoping at all | yes — assets pulled from git URLs | no |
| `generate.ps1` | yes — 2 tools | yes — shared plus repo-local `.standards/` | yes |

`AGENTS.md` is now a cross-tool standard under the Linux Foundation with 60k+ repos,
but it is a whole-file convention; it does not address per-glob scoping.

Copilot organization-level custom instructions went GA in April 2026 and would remove
the need for per-repo files entirely — except they apply only on github.com, not in
IDEs. Developers here write code in Visual Studio and Rider, so that mechanism cannot
reach them where it matters.

## Decision

Keep `generate.ps1`.

Neither tool does both halves of what is needed, and neither validates globs. The
available composition — `ais` to distribute the source, AgentSync to fan it out, plus a
guard script — buys eleven tools nobody here uses, at the cost of two external
dependencies, a Node step in CI, and a seam between them. The generator is 130 lines on
a runtime the plugin already uses for its hooks.

The dead-glob guard is the part worth defending. Neither Claude Code nor Copilot warns
when a scope matches nothing: Claude's `InstructionsLoaded` hook reports only what did
load, and Copilot validates nothing — GitHub's own `awesome-copilot` corpus carries four
dead `applyTo: ['*']` values across 48 CI workflows that never check it. ArchUnit 0.23.0
and ArchUnitNET 0.11.0 both took a **breaking change** to make an empty selector fail
rather than pass. The guard is that steal, and it has already earned its place:
`**/Domain/**/*.cs` matches 7 files in `office-addins`, all `Tools/ConfigGenerator`
enums, and none of the 69 real domain files — a wrong-tree binding a bare
"greater than zero" test passes green.

## What could have refuted this

That AgentSync supported an external shared source. It was the single fact the decision
turned on, it was checked directly rather than assumed, and it came back no.

## Consequences

- We maintain 130 lines of PowerShell nobody else tests.
- Only Claude Code and Copilot are supported. A third tool means writing a third emitter.
- **Revisit when a third AI tool enters real use, or if AgentSync gains an external
  source.** At that point the composition wins and this file should be superseded.
