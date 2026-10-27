#requires -version 5.1
<#
pub.ps1 - build the offline retail installer for the local fork.

Entry point is pub.cmd (ASCII-only launcher); this file holds the logic and
the Chinese text because cmd.exe cannot parse a UTF-8 batch file containing
non-ASCII characters.

Pipeline (same gates as the release flow):
  1. scripts\publish-aot-retail.ps1 -Platform <arch>   (Full Native AOT payload)
  2. ISCC /DDeskBoxNativeAot=1 /DDeskBoxBundledRuntime=1 /DMyAppReleaseDir=<publish>
  3. copy the result to docs\lijinfu\installer\DeskBoxEx_Installer_<version>.exe

Exit codes: 0 ok   1 precondition failed   2 publish failed   3 installer compile failed
#>

[CmdletBinding()]
param(
    [ValidateSet('x64', 'ARM64')]
    [string]$Platform = 'x64',

    [switch]$SkipPublish,

    [string]$OutputDirectory = '',

    [switch]$InstallInnoSetup,

    [switch]$Pause
)

$ErrorActionPreference = 'Stop'

if ([Console]::IsOutputRedirected) {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
}

$script:ExitCode = 0

function Resolve-RepoRoot {
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

function Initialize-Environment {
    $dotnetRoot = Join-Path $env:USERPROFILE '.dotnet'
    $cargoRoot = Join-Path $env:USERPROFILE '.cargo\bin'
    $env:PATH = "$dotnetRoot;$cargoRoot;$env:PATH"
}

function Stop-RepoOwnedProcesses {
    $stopped = @()
    foreach ($name in @('DeskBox', 'DeskBox.ThumbnailProxy')) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            $path = ''
            try { $path = $process.Path } catch { }
            # Never touch an installed copy under Program Files: only the build
            # under this repository is ours to stop.
            if ($path -and $path.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                $stopped += ("{0}({1})" -f $name, $process.Id)
            }
        }
    }
    if ($stopped.Count -gt 0) {
        Write-Host ("[pub] 已停止本仓库进程：{0}" -f ($stopped -join ', '))
    }
}

function Get-InnoCompilerPath {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Read-Version {
    $projectPath = Join-Path $repoRoot 'src\DeskBox\DeskBox.csproj'
    $projectText = Get-Content -LiteralPath $projectPath -Raw
    $projectVersion = [regex]::Match($projectText, '<Version>([^<]+)</Version>').Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($projectVersion)) {
        throw "无法从 $projectPath 读取 <Version>。"
    }

    $installerName = if ($Platform -eq 'ARM64') { 'DeskBox.arm64.iss' } else { 'DeskBox.iss' }
    $installerPath = Join-Path $repoRoot ('installer\' + $installerName)
    $installerText = Get-Content -LiteralPath $installerPath -Raw
    $installerVersion = [regex]::Match($installerText, '(?m)^\s*#define\s+MyAppVersion\s+"([^"]+)"').Groups[1].Value.Trim()

    $manifestPath = Join-Path $repoRoot 'src\DeskBox\Package.appxmanifest'
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    $manifestVersion = [regex]::Match($manifestText, 'Version="(\d+\.\d+\.\d+)(\.\d+)?"').Groups[1].Value

    if ($installerVersion -ne $projectVersion) {
        throw ("版本不一致：{0} 里 MyAppVersion={1}，但 DeskBox.csproj 的 <Version>={2}。" -f $installerName, $installerVersion, $projectVersion)
    }
    if ($manifestVersion -ne $projectVersion) {
        throw ("版本不一致：Package.appxmanifest 是 {0}，但 DeskBox.csproj 的 <Version>={1}。" -f $manifestVersion, $projectVersion)
    }

    Write-Host ("[pub] 版本：{0}（csproj / {1} / appxmanifest 三处一致）" -f $projectVersion, $installerName)
    return $projectVersion
}

function Invoke-Main {
    Initialize-Environment

    $runtimeIdentifier = if ($Platform -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
    $archSegment = if ($Platform -eq 'ARM64') { 'arm64' } else { 'x64' }

    $version = Read-Version

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $finalDirectory = Join-Path $repoRoot 'docs\lijinfu\installer'
    }
    elseif ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
        $finalDirectory = $OutputDirectory
    }
    else {
        $finalDirectory = Join-Path $repoRoot $OutputDirectory
    }
    $finalDirectory = [System.IO.Path]::GetFullPath($finalDirectory)

    $finalName = if ($Platform -eq 'ARM64') {
        "DeskBoxEx_Installer_{0}_arm64.exe" -f $version
    }
    else {
        "DeskBoxEx_Installer_{0}.exe" -f $version
    }
    $finalPath = Join-Path $finalDirectory $finalName

    $stagingDirectory = Join-Path $repoRoot ('.artifacts\pub\' + $runtimeIdentifier)
    $publishDirectory = Join-Path $repoRoot ('.artifacts\aot-retail\' + $runtimeIdentifier + '\publish')
    $innoBaseName = "DeskBox_Setup_{0}_{1}" -f $version, $archSegment

    Stop-RepoOwnedProcesses

    # ---------------------------- 1. AOT payload ----------------------------
    if ($SkipPublish) {
        Write-Host '[pub] 跳过发布（-SkipPublish），复用已有 AOT 载荷。'
    }
    else {
        Write-Host '[pub] 发布 Full Native AOT 载荷（scripts\publish-aot-retail.ps1）...'
        $publishScript = Join-Path $repoRoot 'scripts\publish-aot-retail.ps1'
        & $publishScript -Platform $Platform
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("[FAIL] AOT 零售发布失败（exit {0}）。" -f $LASTEXITCODE)
            $script:ExitCode = 2
            return
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $publishDirectory 'DeskBox.exe') -PathType Leaf)) {
        Write-Host ("[FAIL] 找不到 AOT 载荷目录：{0}" -f $publishDirectory)
        Write-Host '       请先去掉 -SkipPublish 完整跑一次发布。'
        $script:ExitCode = 1
        return
    }
    Write-Host ("[pub] AOT 载荷：{0}" -f $publishDirectory)

    # ---------------------------- 2. Inno Setup -----------------------------
    $innoCompiler = Get-InnoCompilerPath
    if (-not $innoCompiler) {
        if ($InstallInnoSetup) {
            Write-Host '[pub] 未找到 Inno Setup 6，尝试通过 winget 安装（当前用户）...'
            & winget install --id JRSoftware.InnoSetup --exact --scope user --accept-package-agreements --accept-source-agreements
            $innoCompiler = Get-InnoCompilerPath
        }
        if (-not $innoCompiler) {
            Write-Host '[FAIL] 找不到 ISCC.exe（Inno Setup 6 未安装）。'
            Write-Host '       安装方式二选一：'
            Write-Host '         winget install --id JRSoftware.InnoSetup --exact'
            Write-Host "         或重新运行：pub.cmd -InstallInnoSetup"
            Write-Host '       安装后重新执行 pub.cmd 即可（-SkipPublish 可跳过已完成的 AOT 发布）。'
            $script:ExitCode = 1
            return
        }
    }
    Write-Host ("[pub] Inno Setup：{0}" -f $innoCompiler)

    # ---------------------------- 3. Compile --------------------------------
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $stagingDirectory | Out-Null

    $installerScript = Join-Path $repoRoot ('installer\' + $(if ($Platform -eq 'ARM64') { 'DeskBox.arm64.iss' } else { 'DeskBox.iss' }))
    $innoLogPath = Join-Path $stagingDirectory 'inno-compile.log'
    $innoArguments = @(
        '/Qp',
        '/DDeskBoxNativeAot=1',
        '/DDeskBoxBundledRuntime=1',
        "/DMyAppReleaseDir=$publishDirectory",
        "/F$innoBaseName",
        "/O$stagingDirectory",
        $installerScript
    )

    Write-Host '[pub] 编译安装器（Full Native AOT + 内置 Windows App Runtime，可离线安装）...'
    & $innoCompiler @innoArguments 2>&1 | Tee-Object -FilePath $innoLogPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("[FAIL] ISCC 编译失败（exit {0}）。日志：{1}" -f $LASTEXITCODE, $innoLogPath)
        $script:ExitCode = 3
        return
    }

    $producedPath = Join-Path $stagingDirectory ($innoBaseName + '.exe')
    if (-not (Test-Path -LiteralPath $producedPath -PathType Leaf)) {
        Write-Host ("[FAIL] 未生成预期安装包：{0}" -f $producedPath)
        $script:ExitCode = 3
        return
    }

    # ---------------------------- 4. Deliver --------------------------------
    New-Item -ItemType Directory -Force -Path $finalDirectory | Out-Null
    Copy-Item -LiteralPath $producedPath -Destination $finalPath -Force

    $file = Get-Item -LiteralPath $finalPath
    $hash = (Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash
    Write-Host ''
    Write-Host '[OK] 安装包已生成'
    Write-Host ("     路径：{0}" -f $file.FullName)
    Write-Host ("     大小：{0:N1} MB" -f ($file.Length / 1MB))
    Write-Host ("     SHA256：{0}" -f $hash)
    Write-Host ("     编译日志：{0}" -f $innoLogPath)
    Write-Host '     注意：本地构建未签名，首次运行时 SmartScreen 可能提示。'
}

$repoRoot = Resolve-RepoRoot
if (-not $repoRoot) {
    Write-Host '[FAIL] 找不到仓库根目录（脚本必须放在 DeskBoxEx 仓库内）。'
    $script:ExitCode = 1
}
else {
    Set-Location -LiteralPath $repoRoot
    try {
        Invoke-Main
    }
    catch {
        Write-Host ("[FAIL] {0}" -f $_.Exception.Message)
        $script:ExitCode = 1
    }
}

$exitCode = $script:ExitCode
if ($Pause) {
    Write-Host ''
    Write-Host '按任意键关闭窗口...'
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { }
}
exit $exitCode
