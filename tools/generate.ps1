<#
Fans canonical standards out to each tool's own dialect.
Canonical frontmatter: `scope:` (list of globs) + `title:`.
  Claude Code  -> <repo>/.claude/rules/<name>.md                    `paths:` (list)
  Copilot      -> <repo>/.github/instructions/<name>.instructions.md `applyTo:` (comma string)
-Check exits 1 if any target is stale, for CI.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $TargetRepo,
    [string] $StandardsDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'standards'),
    [switch] $Check
)

$ErrorActionPreference = 'Stop'

# Repo-local canonical standards live in the consuming repo and fan out the same way, so
# repo-specific rules stop drifting between the two tools as well.
$LocalDir = Join-Path $TargetRepo '.standards'

$SharedBanner = '<!-- GENERATED FROM dev-standards. Do not edit here; edit standards/{0} in dev-standards and re-run tools/generate.ps1. -->'
$LocalBanner  = '<!-- GENERATED from this repo''s .standards/{0}. Do not edit here; edit that file and re-run dev-standards/tools/generate.ps1. -->'

function Read-Standard {
    param([string] $Path)
    $lines = [System.IO.File]::ReadAllLines($Path)
    if ($lines[0] -ne '---') { throw "$Path has no frontmatter" }
    $end = 1; while ($end -lt $lines.Count -and $lines[$end] -ne '---') { $end++ }
    if ($end -ge $lines.Count) { throw "$Path frontmatter is unterminated" }

    # Canonical scalars may be quoted; each emitter adds its own quoting, so strip here.
    $unquote = { param($v) $v.Trim().Trim("'").Trim('"').Trim() }

    $scope = @(); $title = ''; $inScope = $false
    foreach ($line in $lines[1..($end - 1)]) {
        if ($line -match '^scope:\s*(.*)$') {
            $inScope = $true
            if ($Matches[1].Trim()) { $scope += (& $unquote $Matches[1]); $inScope = $false }
            continue
        }
        if ($inScope -and $line -match '^\s*-\s*(.+)$') { $scope += (& $unquote $Matches[1]); continue }
        if ($line -match '^title:\s*(.+)$') { $title = (& $unquote $Matches[1]); $inScope = $false; continue }
        if ($line -match '^\S') { $inScope = $false }
    }
    if (-not $scope) { throw "$Path declares no scope" }

    [pscustomobject]@{
        Name  = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        Scope = $scope
        Title = $title
        Body  = ($lines[($end + 1)..($lines.Count - 1)] -join "`n").TrimStart("`n")
    }
}

function Write-Target {
    param([string] $Path, [string] $Content)
    # `* text=auto` gives the working tree CRLF, so compare on LF or -Check calls every file stale on Windows.
    $existing = if (Test-Path $Path) { [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n") } else { $null }
    if ($existing -eq $Content) { return 'unchanged' }
    if ($Check) { return 'STALE' }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content)
    return $(if ($null -eq $existing) { 'created' } else { 'updated' })
}

$sources = @()
$sources += Get-ChildItem -Path $StandardsDir -Filter '*.md' -File |
    ForEach-Object { [pscustomobject]@{ File = $_; Banner = $SharedBanner; Origin = 'shared' } }
if (Test-Path $LocalDir) {
    $sources += Get-ChildItem -Path $LocalDir -Filter '*.md' -File |
        ForEach-Object { [pscustomobject]@{ File = $_; Banner = $LocalBanner; Origin = 'local ' } }
}

# A local standard sharing a shared standard's name would silently overwrite it downstream.
$collisions = $sources | Group-Object { $_.File.BaseName } | Where-Object Count -gt 1
if ($collisions) {
    throw "Local standard(s) collide with shared names: $($collisions.Name -join ', '). Rename the local file."
}

function Get-MatchCount {
    param([string] $Root, [string] $Glob)
    # Worktrees hold stale copies of the whole tree (6,965 .cs in one real repo), so a **/-prefixed
    # glob reports ~9x its true match count. They are never the target of a rule.
    # Segment-aware, because `-like` is not: `*Domain\*` also matches `Core.Domain\`, so a glob
    # bound to the wrong tree reports a healthy count instead of the small wrong one that betrays it.
    $rx = [regex]::Escape($Glob) -replace '/', '\\'
    $rx = $rx -replace '\\\*\\\*\\\\', '(?:.*\\)?'   # **/  -> any number of leading segments
    $rx = $rx -replace '\\\*\\\*', '.*'              # **   -> anything
    $rx = $rx -replace '\\\*', '[^\\]*'              # *    -> within one segment
    $rx = '^' + $rx + '$'
    $files = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(obj|bin|node_modules|\.git)\\' -and
                       $_.FullName -notmatch '\\\.claude\\worktrees\\' }
    ($files | Where-Object { $_.FullName.Substring($Root.Length).TrimStart('\') -match $rx }).Count
}

$stale = $false
$deadGlob = @()
foreach ($source in $sources) {
    $std    = Read-Standard $source.File.FullName
    $banner = $source.Banner -f $source.File.Name

    $claudeScope = ($std.Scope | ForEach-Object { "  - '$_'" }) -join "`n"
    $claude = "---`npaths:`n$claudeScope`n---`n$banner`n`n$($std.Body)"

    # GitHub docs: multiple patterns are comma-separated with NO spaces — `applyTo: "**/*.ts,**/*.tsx"`.
    $copilot = "---`napplyTo: '$($std.Scope -join ',')'`n---`n$banner`n`n$($std.Body)"

    # ArchUnit 0.23.0 and ArchUnitNET 0.11.0 both made "selector matched nothing" a failure rather
    # than a pass, as a breaking change - a renamed folder otherwise leaves a green rule checking
    # nothing. Neither Claude Code nor Copilot has that guard, so it lives here. Reporting the count
    # matters as much as the zero check: **/Domain/** matching 7 files where 69 are expected is a
    # wrong-tree binding that a bare >0 test passes green.
    foreach ($glob in $std.Scope) {
        $n = (Get-MatchCount $TargetRepo $glob)
        '{0,-26} {1} scope   {2,6} files  {3}' -f $std.Name, $source.Origin, $n, $glob
        if ($n -eq 0) { $deadGlob += "$($std.Name): '$glob'" }
    }

    $results = @(
        @{ Tool = 'claude ';  Result = Write-Target (Join-Path $TargetRepo ".claude/rules/$($std.Name).md") $claude }
        @{ Tool = 'copilot';  Result = Write-Target (Join-Path $TargetRepo ".github/instructions/$($std.Name).instructions.md") $copilot }
    )
    foreach ($r in $results) {
        if ($r.Result -eq 'STALE') { $stale = $true }
        '{0,-26} {1} {2} {3}' -f $std.Name, $source.Origin, $r.Tool, $r.Result
    }
}

if ($deadGlob) {
    ''
    Write-Error ("Scope matched no files - the rule is silently dead in this repo:`n  " + ($deadGlob -join "`n  "))
    exit 1
}

if ($Check -and $stale) {
    Write-Error 'Generated standards are stale. Run tools/generate.ps1 and commit the result.'
    exit 1
}
