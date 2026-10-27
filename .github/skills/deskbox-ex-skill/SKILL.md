---
name: deskbox-ex-skill
description: 'Use when changing code, writing docs, running tests, or syncing upstream in the DeskBoxEx fork of Tianyu199509/DeskBox. Enforces fork-merge-safe rules: documentation only under docs/lijinfu, one-time seam installation plus feature-level folders instead of author folders, upstream touchpoint ledger, additive minimal diffs, merge-only upstream sync, and the verified local x64 build/test commands.'
---

# DeskBoxEx Fork Workflow

## 何时使用

- 在 DeskBoxEx 仓库里改代码、写文档、跑测试、同步上游或准备提交
- 新增或移植自己的功能（先判断走接缝还是直接改宿主、代码放哪个目录）
- 任何"上游 DeskBox 有同名文件"的改动（README、CHANGELOG、docs/architecture、docs/articles、.github/workflows 等）
- 需要判断某处修改会不会让 fork 与上游合并时冲突

## 仓库身份

| 角色 | 地址 |
|---|---|
| fork（本地 origin） | https://github.com/lijfcn/DeskBoxEx |
| 上游源仓库 | https://github.com/Tianyu199509/DeskBox |

**唯一硬目标：本仓库的每个提交都能与上游 `main` 正常 `git merge`，不产生无谓冲突。**

## 硬规则一：文档只能写在 docs/lijinfu

- 允许：在 `docs/lijinfu/` 下新增或修改文件（分析、决策记录、本地流程说明、缺陷笔记一律放这里）。
- 禁止：修改 `docs/` 下的其他任何文件，以及根目录的 `README.md`、`README.zh-CN.md`、`CHANGELOG.md`、`AGENTS.md`、`CONTRIBUTING.md`、`SECURITY.md`、`SUPPORT.md`。
- 原因：这些文件归上游所有，上游同类改动会直接覆盖或与本地修改冲突。
- 发现上游文档有错时，**不要就地修正**，改写成 `docs/lijinfu/` 下的说明文件并在其中指出来源文件与行号。
  - 已知实例：`README.zh-CN.md` 的测试命令写作 `.\DeskBox.Tests\DeskBox.Tests.csproj`，实际路径是 `.\tests\DeskBox.Tests\DeskBox.Tests.csproj`。这类勘误写进 `docs/lijinfu/`，不改 README。

## 硬规则二：一次性接缝 + 功能级目录（方案 B）

合并冲突只来自**同一文件的同一区域被两端修改**，新建文件永不冲突。因此策略不是"把文件挪到自己的目录"，而是"把对上游文件的修改压到一次、之后只新增文件"。

### 2.1 两类落点

| 类别 | 位置 | 规则 |
|---|---|---|
| **接缝（seam）** | 上游文件 | 一次性安装，之后不再改动；只加单点钩子 |
| **自有实现** | 新增文件 | 默认 `src/DeskBox/Features/<功能域>/`；仅当接缝已稳定、边界封闭时才用 `src/DeskBox/Lijinfu/<功能域>/` |

禁止按作者建一个装混杂功能的顶层大目录：一个作者目录 = 一条与上游 `Features/<域>/` 并行的第二约定，重构后会同功能双实现并静默陈旧。

`src/DeskBox/Features/` 已按功能域划分（Backup、Search、Todo、Weather…），默认跟它同轴，冲突面最小。

### 2.2 接缝安装规则

- 接缝**单独成一个提交**，命名点明"seam"，便于上游重构后手工重放。
- 只允许三种形态：`static partial void` 钩子、注册回调（在构造末尾调用一个可在自有目录里实现的注册方法）、描述符/清单表的调用点。不要为此引入新的抽象层。
- 装接缝时**先证明它真能收敛**：写完后新增同类功能应当只新增文件、零宿主改动；做不到就不是接缝，是换了个地方散落。
- 一次只装一个接缝，装完立刻跑相关子集测试，确认行为零变化。

### 2.3 已知必须触碰的宿主登记点

新增格子类功能时，这些地方逃不掉（依据 [widget_contribution_seam.md](../../../docs/architecture/widget_contribution_seam.md) 的实测：25 个文件、单文件最多 34 处 kind 分支）：

| 登记点 | 说明 |
|---|---|
| `Models/WidgetKind` | 枚举成员 |
| `Services/WidgetContentFactory.DescriptorList` | kind 清单唯一真源，**声明顺序有意义**（`FeatureWidgetSettings` 按它派生） |
| `Services/WidgetRegistry` | 窗口能力表，与描述符表**有意分离**，不要合并 |
| `WidgetManager.FeatureWidgets.cs` | 生命周期分支最密集处（34 处），优先接缝化 |
| `SettingsViewModel` 的 5 个 partial | 每处加字段/回调/同步/胶囊选项 |
| `src/DeskBox/Strings/*.json` | **13 个文化必须键集完全相同**，加一个键就动 13 个上游文件 |
| `App.Aot*Smoke.cs`（6 个） | NativeAOT 宿主 partial，物理搬不走 |

每碰一处都写进 2.5 的台账。

### 2.4 最小 diff 与契约钉值

- 优先新增文件、新增成员；避免重命名、搬移、重排、全文件格式化上游代码。
- 必须改上游文件时只做单点最小 diff，不顺手清理同文件的其他问题、不改上游注释与历史说明块。
- 被契约测试钉住的内容（`Assert.Equal(<计数>, ...)`、nameof 计数、`auditProfileVersion`、XAML 结构 parity）不顺手改；确实要改时同批同步更新钉值。改动 `scripts/publish-aot-audit.ps1` 的 stage 文件列表时，按仓库惯例同步升 `auditProfileVersion`（`AotStage4E3ContractTests` 钉了 59/55）。
- 不修改上游的 `.github/workflows/*.yml`、`.github/ISSUE_TEMPLATE/*`、`.github/PULL_REQUEST_TEMPLATE.md`；本地额外校验写到 `docs/lijinfu/` 或独立新增文件。
- 新目录同样被契约测试递归扫描（`AotInteropShapeContractTests` 扫 `src/DeskBox/**/*.cs`）：自有代码必须满足 NativeAOT 约束（无反射序列化、无裸 WinRT 属性名查找、无 TODO/HACK/FIXME）。这是好事——错误会在本地报，而不是零售版被裁剪后才发现。
- 提交只有用户身份 `Simon <1047078635@qq.com>`，不得带 `Co-Authored-By` / `Generated with` 之类归属尾注（`.githooks/commit-msg` 与 CI 都会拦）。

### 2.5 上游接触点台账（强制）

维护 `docs/lijinfu/upstream-touchpoints.md`，逐条记录：

```markdown
| 上游文件 | 位置 | 改动 | 原因 | 提交 |
|---|---|---|---|---|
| src/DeskBox/Services/WidgetContentFactory.cs | DescriptorList 末尾 | +1 条描述符 | 新增功能 X | abc1234 |
```

**每次 `git merge upstream/main` 之后，对着台账逐条 `git diff` 复核**：上游静默覆盖你的改动不产生冲突、也不报错，是这类 fork 最危险的失败模式。台账同时是"上游改文件名/结构后要重放哪些提交"的唯一依据。

另外一次性执行：

```powershell
git config rerere.enabled true
```

### 2.6 提交纪律

- 一个功能一个提交，接缝安装单独提交。
- 提交粒度小到能在上游重构后手工重放。
- 不把"顺手修上游问题"混进功能提交。

### 2.7 明确不做

- 拆分程序集 / C ABI / 新包格式：上游已否决（`widget_contribution_seam.md` §五，NativeAOT 6 个 smoke 是宿主 partial，三包实测 +13.2MB）。
- 为"可选功能"引入第二套运行时；可选与内置走同一条接缝，用开关控制可见性。


## 硬规则三：上游同步

### 3.1 用脚本（手工与 SKILL 通用）

入口：[pull.cmd](./scripts/pull.cmd) → 实际逻辑在 [scripts/core/pull.ps1](./scripts/core/pull.ps1)

```powershell
# 预览：fetch 后列出将要合入的提交，不合并
.github\skills\deskbox-ex-skill\scripts\pull.cmd --dry-run

# 合并 upstream/main 到当前分支
.github\skills\deskbox-ex-skill\scripts\pull.cmd

# 合并后立刻跑全量测试
.github\skills\deskbox-ex-skill\scripts\pull.cmd --test

# SKILL 内调用
cmd /c ".github\skills\deskbox-ex-skill\scripts\pull.cmd --dry-run"
```

| 参数 | 作用 |
|---|---|
| （无） | fetch 并合并 `upstream/main` |
| `--dry-run` | 只 fetch + 预览将合入的提交，不合并 |
| `--no-fetch` | 跳过 fetch，用本地已有引用 |
| `--ref <ref>` | 合并指定引用（如 `upstream/v1.6.0`） |
| `--test` | 合并成功后跑全量 x64 测试 |
| `--pause` | 结束后停住等按键（双击运行时自动生效） |
| `--abort` | 放弃进行中的合并 |
| `--help` | 帮助 |

退出码：`0` 成功/已最新、`1` 前置条件不满足、`2` 冲突、`3` 合并非冲突失败。

窗口行为：双击运行时脚本会等到按键才关窗（否则一闪而过看不到结果）；从命令行、PowerShell 或 SKILL 调用不暂停，便于自动化。判定依据是 `cmd /c ""<脚本>" "` 这一双击特有的命令行形态。

脚本保证的行为：

- 自动创建 `upstream` remote（默认 `https://github.com/Tianyu199509/DeskBox.git`，可用环境变量 `DESKBOX_UPSTREAM_URL` 覆盖）
- **自动定位仓库**：从脚本自身位置向上查找 `.git`（或 `src\DeskBox\DeskBox.csproj`），不依赖调用方的工作目录，因此资源管理器双击、VS Code"在外部应用中打开"、快捷方式、终端都能正常工作
- 有未提交的**已跟踪**改动时拒绝执行（未跟踪文件不影响）
- 存在 `MERGE_HEAD` 时拒绝并列出冲突文件，提示 `--abort`
- 只执行 `git merge`，从不 rebase / squash
- 合并成功后打印台账复核与全量测试提醒
- 双击运行不会闪退（结束时等待按键）；自动化调用不暂停

维护约束：

布局：`scripts/pull.cmd`（纯 ASCII 启动器）→ `scripts/core/pull.ps1`（全部逻辑与中文文案）。

- `pull.cmd` / `pub.cmd` **必须保持纯 ASCII**。cmd.exe 按字节偏移定位脚本站、却按字符解码，含中文的 UTF-8 批处理会逐行错位——实测会导致后续命令丢掉开头字符（`echo   pull.cmd ...` 被执行成 `l.cmd ...`），把无关的 `for /f` 与 `git` 调用一起弄坏。因此所有中文只放同名 `.ps1`。
- `scripts/core/*.ps1` 必须以 **UTF-8 with BOM** 保存，PowerShell 5.1 才按 UTF-8 解析其中的中文。
- 移动 `pull.ps1` / `pub.ps1` 时同步改对应 `.cmd` 里的 `%~dp0core\*.ps1`。
- 仓库定位在 `Resolve-RepoRoot`（向上查找 `.git`）里，改了目录层级无需改它；但若把脚本整体移出仓库，脚本会明确报"找不到 git 仓库"而不是误操作别的仓库。
- 全部脚本保持 CRLF 行尾。

### 3.2 上游同步的手工等价命令

```powershell
# 首次
git remote add upstream https://github.com/Tianyu199509/DeskBox.git

# 每次同步
git fetch upstream
git merge upstream/main
```

- 用 `merge`，不要对已推送分支 `rebase` 或 `squash`。
- 冲突处理顺序：上游文件以上游为准 → 本地定制挪到新增文件或 `docs/lijinfu/` → 只有行为确实需要时才保留本地改动的最小片段。
- **合并后必须复核台账**：按 `docs/lijinfu/upstream-touchpoints.md` 逐条 `git diff`，确认上游没有静默覆盖本地改动（无冲突的静默覆盖不会报错）。
- 合并后再跑一遍全量测试，确认契约钉值仍成立。

### 3.3 打包安装包（pub.cmd，2026-10-27 实测）

入口：[pub.cmd](./scripts/pub.cmd) → 逻辑在 [scripts/core/pub.ps1](./scripts/core/pub.ps1)。产物固定落在 `docs/lijinfu/installer/DeskBoxEx_Installer_<版本>.exe`（ARM64 为 `_arm64.exe`）。

```powershell
# 完整打包：AOT 零售发布 + Inno 编译
.github\skills\deskbox-ex-skill\scripts\pub.cmd

# 复用已有 AOT 载荷，只重编安装器
.github\skills\deskbox-ex-skill\scripts\pub.cmd -SkipPublish

# 缺 Inno Setup 6 时按当前用户安装
.github\skills\deskbox-ex-skill\scripts\pub.cmd -InstallInnoSetup
```

它做的事（与发版链路同门禁）：

1. 调 `scripts/publish-aot-retail.ps1 -Platform <arch>` 生成 Full Native AOT 载荷（`.artifacts/aot-retail/<rid>/publish`，约 392 个文件 / 131 MiB，10 分钟量级）
2. `ISCC /DDeskBoxNativeAot=1 /DDeskBoxBundledRuntime=1 /DMyAppReleaseDir=<publish> /FDeskBox_Setup_<ver>_<arch> /O<staging> installer\DeskBox.iss`
3. 改名复制到 `docs/lijinfu/installer/`，打印大小与 SHA-256

要点：

- **版本三处必须一致**：`src/DeskBox/DeskBox.csproj` 的 `<Version>`、`installer/DeskBox.iss` 的 `MyAppVersion`、`Package.appxmanifest` 的 `Version`。脚本先校验，不一致直接失败——不要用命令行覆盖版本号，那是发版动作。
- 内置 Windows App Runtime 来自 AOT 载荷里的私有运行时 DLL（不是下载 msix），因此产物可完全离线安装。
- 产物**未签名**，首次运行会有 SmartScreen 提示；正式发布走 `scripts/publish-aot-retail.ps1` + 签名流程。
- `docs/lijinfu/installer/*.exe` 被仓库 `.gitignore` 的 `*.exe` 规则忽略，不会误进提交。
- 需 Inno Setup 6（`winget install --id JRSoftware.InnoSetup --exact`，装到 `%LOCALAPPDATA%\Programs\Inno Setup 6`）。脚本会在 PATH、Program Files、LOCALAPPDATA 三处查找 `ISCC.exe`。
- 退出码：`0` 成功、`1` 前置条件不满足、`2` AOT 发布失败、`3` Inno 编译失败。

## 硬规则四：本机构建与测试（2026-10-27 实测）

环境前提：

- .NET SDK **10.0.402**（`global.json` 用 `rollForward: latestPatch`；10.0.403 会把 `Microsoft.NET.ILLink.Tasks` 从 10.0.13 抬到 10.0.14，导致 `DeskBox.Updater` 锁文件报 `NU1004`，锁定模式还原失败）。
- Rust **1.96.0**（`rustup`，需 `x86_64-pc-windows-msvc` 与 `aarch64-pc-windows-msvc` 两个 target）。测试工程会在编译前用 cargo 构建 `deskbox_native.dll`，没有 cargo 直接失败。
- VS Build Tools（MSVC + Windows SDK），用仓库自带的 `scripts/rust-arm64-msvc-environment.ps1` 注入环境，不必开 VS 开发者命令行。

```powershell
$env:PATH = "$env:USERPROFILE\.dotnet;$env:USERPROFILE\.cargo\bin;$env:PATH"
Set-Location D:\Projects\lijinfu\DeskBoxEx
. .\scripts\rust-arm64-msvc-environment.ps1
Enter-DeskBoxMsvcEnvironment -Toolchain (Get-DeskBoxMsvcEnvironment -Platform x64) | Out-Null

# 首次/依赖变化时
dotnet restore .\DeskBox.sln --locked-mode -p:Platform=x64 -p:RuntimeIdentifier=win-x64

# 全量（提交前）
dotnet test .\tests\DeskBox.Tests\DeskBox.Tests.csproj --no-restore --verbosity:minimal `
  -p:Platform=x64 -p:RuntimeIdentifier=win-x64

# 子集（日常）
dotnet test .\tests\DeskBox.Tests\DeskBox.Tests.csproj --no-restore --verbosity:minimal `
  -p:Platform=x64 -p:RuntimeIdentifier=win-x64 `
  --filter "FullyQualifiedName~SettingsServiceTests"
```

判定与坑：

- **必须显式 `-p:Platform=x64`**（`AnyCPU` 被 MSIX 打包约束拒绝）。
- 绿的标准是 **通过数 == 总数**；中断的 run 也会打印 `失败: 0`。
- 跑之前先停掉从本仓库启动的 `DeskBox.exe`，否则输出文件被锁，构建可能"0 错误但没写入"。
- `Category=Hardware` 的跨卷测试在缺少 `DESKBOX_TEST_SOURCE_VOLUME` / `DESKBOX_TEST_DESTINATION_VOLUME` 时直接 `return`，仍计入通过，别当成真跑过。

## 文档落点

| 内容 | 位置 |
|---|---|
| 分析、决策、排查记录 | `docs/lijinfu/<主题>.md` |
| 上游文档勘误说明 | `docs/lijinfu/<主题>.md`，内含原文件与行号 |
| 本地构建/测试补充 | `docs/lijinfu/<主题>.md` |
| **上游接触点台账** | `docs/lijinfu/upstream-touchpoints.md`（见 2.5，强制维护） |

不要为规划或笔记新建仓库根目录或其他 docs 子目录下的文件。
