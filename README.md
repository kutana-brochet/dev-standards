# dev-standards

Canonical engineering standards. One source; each tool's format is generated.

Standards were previously hand-maintained in parallel per tool, and drifted: in `office-addins`,
`.claude/rules/csharp.md` and `.github/instructions/csharp.instructions.md` governed the same
`**/*.cs` glob with different content, so a Claude Code dev and a Copilot dev were held to
different standards in the same repo.

## Layout

```
standards/          canonical, tool-neutral, one file per scope
tools/generate.ps1  fans out to each tool's dialect
```

Canonical frontmatter:

```yaml
---
scope:
  - '**/*.cs'
title: C# Standards
---
```

## Generating

```powershell
./tools/generate.ps1 -TargetRepo E:\Repos\office-addins           # write
./tools/generate.ps1 -TargetRepo E:\Repos\office-addins -Check    # CI: exit 1 if stale
```

| Target | Path | Frontmatter |
|---|---|---|
| Claude Code | `.claude/rules/<name>.md` | `paths:` (list) |
| GitHub Copilot | `.github/instructions/<name>.instructions.md` | `applyTo:` (comma-separated) |

Generated files carry a banner and must not be edited in place — `-Check` fails the build if they are.

## What belongs here vs in a repo

**Here**: anything true of more than one repo — C# principles, VSTO/COM rules, testing conventions.

**In the repo** (ungenerated, alongside the generated files): facts true only of that repo — its
build incantation, release process, commit signing, project-layout quirks. In `office-addins` those
are `build.md`, `release.md`, `commits.md`.

## Adding a repo

Consuming repos do **not** check out this repo. Generated files are committed, so anyone cloning
`office-addins` needs nothing extra — no submodule, no setup step, no clone order.

Only two places ever need `dev-standards`:

1. **Whoever edits a standard** — clone, edit `standards/`, run the generator against each consuming
   repo, commit the results there.
2. **CI, to prove nothing was hand-edited** — a shallow clone at a tag, then `-Check`.

```yaml
# .github/workflows/standards-drift.yml (in the consuming repo)
- name: Check standards are current
  shell: pwsh
  run: |
    git clone --depth 1 --branch v1 https://github.com/<owner>/dev-standards.git $env:RUNNER_TEMP/ds
    & "$env:RUNNER_TEMP/ds/tools/generate.ps1" -TargetRepo $env:GITHUB_WORKSPACE -Check
```

Pinning the tag means a consuming repo upgrades deliberately: bump `v1` to `v2` when it is ready,
not whenever a standard changes.
