#requires -version 5.1
<#
pull.ps1 - merge upstream author code (Tianyu199509/DeskBox) into the current
branch. Entry point is pull.cmd; the batch file is an ASCII-only launcher
because cmd.exe cannot parse a UTF-8 batch file containing non-ASCII text.

Exit codes: 0 ok / up-to-date   1 precondition failed
            2 merge conflict    3 merge failed (non-conflict)
Merge only. Never rebase, never squash (see SKILL.md rule 3).

Control flow note: the result is carried in $script:ExitCode, never in the
function's return value. Native command output (git/dotnet) must reach the
console, and a returned value would absorb it.
#>

$ErrorActionPreference = 'Continue'

# Redirected output (SKILL / tool invocation) must be UTF-8; a real console keeps
# its own code page so the text renders with the active console font.
if ([Console]::IsOutputRedirected) {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
}

$upstreamName = 'upstream'
$upstreamUrl = 'https://github.com/Tianyu199509/DeskBox.git'
if (-not [string]::IsNullOrWhiteSpace($env:DESKBOX_UPSTREAM_URL)) {
    $upstreamUrl = $env:DESKBOX_UPSTREAM_URL
}
$ref = 'upstream/main'
$ledger = 'docs\lijinfu\upstream-touchpoints.md'

$dryRun = $false
$noFetch = $false
$abort = $false
$runTests = $false
$requestPause = $false
$showHelp = $false
$unknownArgument = $false
$script:ExitCode = 0

$rawArgs = @($args)
$index = 0
while ($index -lt $rawArgs.Count) {
    $current = [string]$rawArgs[$index]
    if ($current -eq '') { $index++; continue }
    if ($current -ieq '--dry-run') { $dryRun = $true; $index++; continue }
    if ($current -ieq '--no-fetch') { $noFetch = $true; $index++; continue }
    if ($current -ieq '--abort') { $abort = $true; $index++; continue }
    if ($current -ieq '--test') { $runTests = $true; $index++; continue }
    if ($current -ieq '--pause') { $requestPause = $true; $index++; continue }
    if ($current -ieq '--help' -or $current -ieq '-h' -or $current -eq '/?') {
        $showHelp = $true; $index++; continue
    }
    if ($current -ieq '--ref') {
        if ($index + 1 -ge $rawArgs.Count -or [string]::IsNullOrWhiteSpace([string]$rawArgs[$index + 1])) {
            Write-Host '[FAIL] --ref 需要一个引用名，例如 --ref upstream/main 或 --ref upstream/v1.6.0'
            exit 1
        }
        $ref = [string]$rawArgs[$index + 1]
        $index += 2
        continue
    }
    Write-Host ("[FAIL] 未知参数：{0}" -f $current)
    $showHelp = $true
    $unknownArgument = $true
    break
}

function Resolve-RepoRoot {
    # Resolve from the script's own location, not the caller's working
    # directory: Explorer double-click, VS Code "open in external app" and
    # shortcuts all hand over a different CWD (often C:\Windows), which would
    # make a CWD-based git lookup fail with "not a git repository".
    $candidate = $PSScriptRoot
    while (-not [string]::IsNullOrWhiteSpace($candidate)) {
        if (Test-Path -LiteralPath (Join-Path $candidate '.git')) { return $candidate }
        if (Test-Path -LiteralPath (Join-Path $candidate 'src\DeskBox\DeskBox.csproj')) { return $candidate }
        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) { break }
        $candidate = $parent
    }
    return $null
}

function Show-Usage {
    Write-Host ''
    Write-Host 'pull.cmd - 合并上游 Tianyu199509/DeskBox 到当前分支（只 merge，不 rebase）'
    Write-Host ''
    Write-Host '用法：'
    Write-Host '  pull.cmd                  获取并合并 upstream/main'
    Write-Host '  pull.cmd --dry-run        只获取并预览将要合入的提交，不合并'
    Write-Host '  pull.cmd --no-fetch       不 fetch，直接用本地已有的 upstream 引用'
    Write-Host '  pull.cmd --ref <ref>      合并指定引用，如 --ref upstream/v1.6.0'
    Write-Host '  pull.cmd --test           合并成功后立即跑全量 x64 测试'
    Write-Host '  pull.cmd --pause          结束后保留窗口（双击时自动保留）'
    Write-Host '  pull.cmd --abort          放弃进行中的合并'
    Write-Host '  pull.cmd --help           显示本帮助'
    Write-Host ''
    Write-Host '退出码：0 成功/已最新   1 前置条件不满足   2 冲突   3 合并非冲突失败'
}

function Invoke-Main {
    if ($showHelp) {
        Show-Usage
        if ($unknownArgument) { $script:ExitCode = 1 }
        return
    }

    $resolvedRoot = Resolve-RepoRoot
    if ($resolvedRoot) {
        Set-Location -LiteralPath $resolvedRoot
    }

    $rootLines = @(& git rev-parse --show-toplevel 2>$null)
    $root = if ($rootLines.Count -gt 0) { [string]$rootLines[0] } else { '' }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
        Write-Host '[FAIL] 找不到 git 仓库。'
        Write-Host ("       脚本位置：{0}" -f $PSScriptRoot)
        Write-Host ("       当前目录：{0}" -f (Get-Location).Path)
        Write-Host '       本脚本应放在 DeskBoxEx 仓库内；若被复制到别处，请放回仓库后重试。'
        $script:ExitCode = 1
        return
    }
    Set-Location -LiteralPath $root

    & git symbolic-ref -q HEAD *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[FAIL] 当前处于 detached HEAD，请先切换到分支。'
        $script:ExitCode = 1
        return
    }

    & git rev-parse --verify -q MERGE_HEAD *> $null
    if ($LASTEXITCODE -eq 0) {
        if ($abort) {
            Write-Host '[INFO] 放弃进行中的合并...'
            & git merge --abort
            if ($LASTEXITCODE -ne 0) {
                Write-Host '[FAIL] git merge --abort 失败，请手工检查。'
                $script:ExitCode = 3
                return
            }
            Write-Host '[OK] 已放弃合并，工作区回到合并前状态。'
            return
        }
        Write-Host '[FAIL] 仓库内有进行中的合并（存在 MERGE_HEAD），请先解决冲突并提交。'
        Write-Host '       冲突文件：'
        & git --no-pager diff --name-only --diff-filter=U
        Write-Host '       放弃本次合并： pull.cmd --abort'
        $script:ExitCode = 2
        return
    }
    if ($abort) {
        Write-Host '[INFO] 当前没有进行中的合并，--abort 无需执行。'
        return
    }

    $dirty = @(& git status --porcelain --untracked-files=no)
    if ($dirty.Count -gt 0) {
        Write-Host '[FAIL] 有未提交的改动，请先提交或 git stash：'
        foreach ($line in $dirty) { Write-Host ("       {0}" -f $line) }
        $script:ExitCode = 1
        return
    }

    $branchLines = @(& git rev-parse --abbrev-ref HEAD)
    $branch = if ($branchLines.Count -gt 0) { [string]$branchLines[0] } else { '(unknown)' }
    Write-Host ("[INFO] 仓库：{0}" -f $root)
    Write-Host ("[INFO] 分支：{0}" -f $branch)

    & git remote get-url $upstreamName *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("[INFO] 添加上游 remote {0}，指向 {1}" -f $upstreamName, $upstreamUrl)
        & git remote add $upstreamName $upstreamUrl
        if ($LASTEXITCODE -ne 0) {
            Write-Host '[FAIL] git remote add 失败。'
            $script:ExitCode = 1
            return
        }
    }

    if ($noFetch) {
        Write-Host ("[INFO] 跳过 fetch（--no-fetch），使用本地已有的 {0} 引用。" -f $upstreamName)
    }
    else {
        Write-Host '[INFO] 获取上游更新...'
        & git fetch $upstreamName --prune
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("[FAIL] git fetch {0} 失败，检查网络或 remote 配置。" -f $upstreamName)
            $script:ExitCode = 1
            return
        }
    }

    & git rev-parse --verify -q $ref *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("[FAIL] 找不到引用 {0}，请确认 --ref 拼写或先 fetch。" -f $ref)
        $script:ExitCode = 1
        return
    }

    $incomingLines = @(& git rev-list --count "HEAD..$ref")
    $localLines = @(& git rev-list --count "$ref..HEAD")
    $incoming = if ($incomingLines.Count -gt 0) { [int]$incomingLines[0] } else { 0 }
    $localOnly = if ($localLines.Count -gt 0) { [int]$localLines[0] } else { 0 }
    Write-Host ("[INFO] 待合入上游提交：{0} 个；本地独有提交：{1} 个。" -f $incoming, $localOnly)

    if ($incoming -eq 0) {
        Write-Host ("[OK] 已经包含 {0}，无需合并。" -f $ref)
        return
    }

    Write-Host ''
    Write-Host '[INFO] 上游新增提交（最多显示 20 条）：'
    & git --no-pager log --oneline --no-decorate -20 "HEAD..$ref"
    Write-Host ''

    if ($dryRun) {
        Write-Host '[OK] --dry-run：仅预览，未执行合并。'
        return
    }

    Write-Host ("[INFO] 合并 {0} 到 {1}（merge，不 rebase）..." -f $ref, $branch)
    & git merge --no-edit $ref
    if ($LASTEXITCODE -ne 0) {
        & git rev-parse --verify -q MERGE_HEAD *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host '[FAIL] 合并失败（非冲突），查看上方 git 输出。'
            $script:ExitCode = 3
            return
        }
        Write-Host ''
        Write-Host '[FAIL] 合并产生冲突，已停止。冲突文件：'
        & git --no-pager diff --name-only --diff-filter=U
        Write-Host ''
        Write-Host '[NEXT] 按 SKILL.md 的冲突顺序处理：'
        Write-Host '       1) 上游文件以上游为准：git checkout --theirs -- <file>'
        Write-Host '       2) 本地定制挪到新增文件或 docs\lijinfu\'
        Write-Host '       3) git add <file>'
        Write-Host '       4) git commit --no-edit'
        Write-Host '       放弃本次合并： pull.cmd --abort'
        $script:ExitCode = 2
        return
    }

    Write-Host ''
    Write-Host '[OK] 合并完成，当前 HEAD：'
    & git --no-pager log --oneline -1
    Write-Host ''
    Write-Host '[NEXT] 1) 按台账复核上游是否静默覆盖了本地改动：'
    Write-Host ("           {0}" -f $ledger)
    Write-Host '           逐条 git diff 对应文件，确认本地改动仍在；上游同区域改写不会报冲突。'
    Write-Host '        2) 跑全量测试，确认契约钉值仍成立：'
    Write-Host '           dotnet test .\tests\DeskBox.Tests\DeskBox.Tests.csproj --no-restore --verbosity:minimal -p:Platform=x64 -p:RuntimeIdentifier=win-x64'
    Write-Host '        3) 本次若新增/调整了上游接触点，同步更新台账。'
    if (Test-Path -LiteralPath $ledger) {
        Write-Host ("[INFO] 台账存在：{0}" -f $ledger)
    }
    else {
        Write-Host ("[WARN] 台账不存在：{0}（首次改动上游文件时创建）" -f $ledger)
    }

    if (-not $runTests) { return }

    Write-Host ''
    Write-Host '[INFO] 运行全量测试...'
    $dotnetRoot = Join-Path $env:USERPROFILE '.dotnet'
    if (Test-Path -LiteralPath $dotnetRoot) {
        $env:PATH = "$dotnetRoot;$env:USERPROFILE\.cargo\bin;$env:PATH"
    }
    $msvcHelper = Join-Path (Get-Location).Path 'scripts\rust-arm64-msvc-environment.ps1'
    if (Test-Path -LiteralPath $msvcHelper) {
        . $msvcHelper
        Enter-DeskBoxMsvcEnvironment -Toolchain (Get-DeskBoxMsvcEnvironment -Platform x64) | Out-Null
    }
    & dotnet test .\tests\DeskBox.Tests\DeskBox.Tests.csproj --no-restore --verbosity:minimal `
        -p:Platform=x64 -p:RuntimeIdentifier=win-x64
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[FAIL] 测试未全绿，合并已保留，请先修复再继续。'
        $script:ExitCode = 1
        return
    }
    Write-Host '[OK] 测试全绿（核对“通过数 == 总数”）。'
}

Invoke-Main
$exitCode = $script:ExitCode

if ($requestPause) {
    Write-Host ''
    Write-Host '按任意键关闭窗口...'
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { }
}

exit $exitCode
