#Requires -Version 5.1
<#
.SYNOPSIS
  GitHub Copilot 插件汉化一键部署（Windows x64）
.DESCRIPTION
  自动扫描本机所有 JetBrains IDE 的 GitHub Copilot 插件，备份原文件后写入中文资源。
  兼容旧版 lib/core.jar 和新版 lib/modules/*.jar 结构。
.PARAMETER DryRun
  只检测和预览，不写入任何文件。
.PARAMETER Restore
  从备份恢复原版插件文件。
.PARAMETER BackupDir
  配合 -Restore 使用，指定备份目录；省略时恢复最近一次备份。
.PARAMETER PluginDir
  手动指定 github-copilot-intellij 插件目录，跳过自动扫描。
.PARAMETER Ide
  只处理名称包含该字符串的 IDE，例如 IntelliJIdea。
.PARAMETER Yes
  跳过确认提示。
.PARAMETER IgnoreRunningIde
  忽略正在运行的 IDE（仅供测试或特殊场景，正式安装请勿使用）。
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Restore,
    [string]$BackupDir,
    [string]$PluginDir,
    [string]$Ide,
    [switch]$Yes,
    [switch]$IgnoreRunningIde
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:LogPath = $null
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host $Message -ForegroundColor $Color
    if ($script:LogPath) {
        try {
            Add-Content -Path $script:LogPath -Value ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) -Encoding UTF8
        } catch { }
    }
}

function Get-Sha256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::OpenRead($Path)
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '')
    } finally {
        $fs.Dispose()
        $sha.Dispose()
    }
}

function Get-RunningIdes {
    $names = @(
        'idea64', 'idea', 'pycharm64', 'pycharm', 'webstorm64', 'webstorm',
        'goland64', 'goland', 'datagrip64', 'datagrip', 'clion64', 'clion',
        'rider64', 'rider', 'phpstorm64', 'phpstorm', 'rubymine64', 'rubymine',
        'appcode64', 'appcode', 'rustrover64', 'rustrover', 'aqua64', 'aqua',
        'dataspell64', 'dataspell'
    )
    $list = @()
    foreach ($p in @(Get-Process -Name $names -ErrorAction SilentlyContinue)) {
        $cmd = ''
        try {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).CommandLine
        } catch { }
        if ($cmd -notmatch 'stdioMcpServer') {
            $list += [pscustomobject]@{ Id = $p.Id; Name = $p.ProcessName }
        }
    }
    return $list
}

function Get-PluginDirs {
    $result = @()
    if ($PluginDir) {
        if (-not (Test-Path $PluginDir)) { throw "插件目录不存在：$PluginDir" }
        $full = (Resolve-Path $PluginDir).Path
        $product = Split-Path (Split-Path $full -Parent) -Parent
        $result += [pscustomobject]@{ Product = (Split-Path $product -Leaf); Path = $full }
        return $result
    }

    $base = Join-Path $env:APPDATA 'JetBrains'
    if (-not (Test-Path $base)) { return @() }

    foreach ($dir in @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue)) {
        $pluginPath = Join-Path $dir.FullName 'plugins\github-copilot-intellij'
        if (Test-Path $pluginPath) {
            if ($Ide -and $dir.Name -notlike "*$Ide*") { continue }
            $result += [pscustomobject]@{ Product = $dir.Name; Path = (Resolve-Path $pluginPath).Path }
        }
    }
    return $result
}

function Get-PluginVersion {
    param([string]$PluginPath)
    $lib = Join-Path $PluginPath 'lib'
    foreach ($j in @(Get-ChildItem $lib -Filter '*.jar' -File -ErrorAction SilentlyContinue)) {
        try {
            $z = [IO.Compression.ZipFile]::OpenRead($j.FullName)
            try {
                $e = $z.GetEntry('META-INF/plugin.xml')
                if ($e) {
                    $sr = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
                    $xml = $sr.ReadToEnd()
                    $sr.Close()
                    $m = [regex]::Match($xml, '<version>([^<]+)</version>')
                    if ($m.Success) { return $m.Groups[1].Value.Trim() }
                }
            } finally { $z.Dispose() }
        } catch { }
    }
    return 'unknown'
}

function Find-JarTargets {
    param([string]$PluginPath)
    $lib = Join-Path $PluginPath 'lib'
    $targets = @()

    foreach ($j in @(Get-ChildItem $lib -Recurse -Filter '*.jar' -File -ErrorAction SilentlyContinue)) {
        try {
            $z = [IO.Compression.ZipFile]::OpenRead($j.FullName)
            try {
                $hasProperties = $null -ne $z.GetEntry('copilot/copilot.properties')
                $xmlNames = @()

                foreach ($e in $z.Entries) {
                    if ($e.FullName -match '\.xml$' -and $e.Length -lt 2097152 -and
                        $e.FullName -notmatch '/maven/' -and $e.Name -ne 'pom.xml') {
                        $sr = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
                        $txt = $sr.ReadToEnd()
                        $sr.Close()
                        if ($txt -match '<override-text\s+place="MainMenu"') { $xmlNames += $e.FullName }
                    }
                }

                if ($hasProperties -or $xmlNames.Count -gt 0) {
                    $targets += [pscustomobject]@{
                        Jar = $j.FullName
                        HasProperties = $hasProperties
                        XmlEntries = $xmlNames
                    }
                }
            } finally { $z.Dispose() }
        } catch { }
    }
    return $targets
}

function Load-Translations {
    param([string]$Path)
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
        if ($line.Trim() -eq '' -or $line -match '^\s*[#!]') { continue }
        $i = $line.IndexOf('=')
        if ($i -lt 0) { continue }
        $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1)
    }
    return $map
}

function Load-Menu {
    param([string]$Path)
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $json = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }
    return $map
}

function Test-Continuation {
    param([string]$Line)
    $n = 0
    for ($i = $Line.Length - 1; $i -ge 0; $i--) {
        if ($Line[$i] -eq [char]92) { $n++ } else { break }
    }
    return (($n % 2) -eq 1)
}

function Merge-Properties {
    param([string]$Text, $Translations)
    $lines = $Text -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $applied = 0
    $i = 0

    while ($i -lt $lines.Length) {
        $line = $lines[$i]
        if ($line.Trim() -eq '' -or $line -match '^\s*[#!]') {
            $out.Add($line)
            $i++
            continue
        }

        $entry = New-Object System.Collections.Generic.List[string]
        $entry.Add($line)
        while (Test-Continuation $lines[$i]) {
            $i++
            if ($i -ge $lines.Length) { break }
            $entry.Add($lines[$i])
        }

        $eq = $entry[0].IndexOf('=')
        if ($eq -lt 0) {
            foreach ($l in $entry) { $out.Add($l) }
            $i++
            continue
        }

        $key = $entry[0].Substring(0, $eq).Trim()
        if ($Translations.ContainsKey($key)) {
            $out.Add($key + '=' + $Translations[$key])
            $applied++
        } else {
            foreach ($l in $entry) { $out.Add($l) }
        }
        $i++
    }

    $joined = $out -join "`n"
    if (-not $joined.EndsWith("`n")) { $joined = $joined + "`n" }
    return [pscustomobject]@{
        Text = $joined
        Applied = $applied
    }
}

function Replace-MenuText {
    param([string]$Text, $Menu)
    $state = @{ Count = 0 }
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $raw = $m.Groups[1].Value
        $decoded = [System.Net.WebUtility]::HtmlDecode($raw)
        if ($Menu.ContainsKey($decoded)) {
            $state.Count++
            return 'text="' + [System.Security.SecurityElement]::Escape($Menu[$decoded]) + '"'
        }
        return $m.Value
    }
    $newText = [regex]::Replace($Text, 'text="([^"]*)"', $evaluator)
    return [pscustomobject]@{ Text = $newText; Count = $state.Count }
}

function Get-PropertiesKeys {
    param([string]$Text)
    $keys = New-Object System.Collections.Generic.List[string]
    $lines = $Text -split "`r?`n"
    $i = 0
    while ($i -lt $lines.Length) {
        $line = $lines[$i]
        if ($line.Trim() -eq '' -or $line -match '^\s*[#!]') { $i++; continue }
        $entry = New-Object System.Collections.Generic.List[string]
        $entry.Add($line)
        while (Test-Continuation $lines[$i]) {
            $i++
            if ($i -ge $lines.Length) { break }
            $entry.Add($lines[$i])
        }
        $eq = $entry[0].IndexOf('=')
        if ($eq -ge 0) { $keys.Add($entry[0].Substring(0, $eq).Trim()) }
        $i++
    }
    return $keys
}

function Repack-Jar {
    param([string]$Source, [string]$Destination, $Replacements)
    if (Test-Path $Destination) { Remove-Item $Destination -Force }

    $zin = [IO.Compression.ZipFile]::OpenRead($Source)
    try {
        $zout = [IO.Compression.ZipFile]::Open($Destination, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($e in $zin.Entries) {
                $ne = $zout.CreateEntry($e.FullName, [IO.Compression.CompressionLevel]::Optimal)
                try { $ne.LastWriteTime = $e.LastWriteTime } catch { }
                $os = $ne.Open()
                try {
                    if ($Replacements.ContainsKey($e.FullName)) {
                        $bytes = [Text.Encoding]::UTF8.GetBytes($Replacements[$e.FullName])
                        $os.Write($bytes, 0, $bytes.Length)
                    } else {
                        $is = $e.Open()
                        try { $is.CopyTo($os) } finally { $is.Dispose() }
                    }
                } finally { $os.Dispose() }
            }
        } finally { $zout.Dispose() }
    } finally { $zin.Dispose() }
}

function Verify-Jar {
    param([string]$Jar, [string]$ExpectedXmlEntry, [int]$ExpectedKeyCount)
    $z = [IO.Compression.ZipFile]::OpenRead($Jar)
    try {
        $details = @()
        $ok = $true

        $pe = $z.GetEntry('copilot/copilot.properties')
        if ($pe) {
            $sr = New-Object IO.StreamReader($pe.Open(), [Text.Encoding]::UTF8)
            $txt = $sr.ReadToEnd()
            $sr.Close()
            $keys = Get-PropertiesKeys $txt
            $details += "keys=$($keys.Count)"
            if ($ExpectedKeyCount -gt 0 -and $keys.Count -ne $ExpectedKeyCount) {
                $ok = $false
                $details += "key count mismatch (expected $ExpectedKeyCount)"
            }
            $dups = @($keys | Group-Object | Where-Object { $_.Count -gt 1 })
            if ($dups.Count -gt 0) {
                $ok = $false
                $details += "duplicate keys=$($dups.Count)"
            }
        }

        if ($ExpectedXmlEntry) {
            $xe = $z.GetEntry($ExpectedXmlEntry)
            if (-not $xe) {
                $ok = $false
                $details += 'xml missing'
            } else {
                $sr = New-Object IO.StreamReader($xe.Open(), [Text.Encoding]::UTF8)
                $xt = $sr.ReadToEnd()
                $sr.Close()
                try {
                    $null = [xml]$xt
                    $details += 'xml=ok'
                } catch {
                    $ok = $false
                    $details += 'xml=invalid'
                }
            }
        }

        return [pscustomobject]@{ Ok = $ok; Details = ($details -join ', ') }
    } finally { $z.Dispose() }
}

function New-Backup {
    param($Items)
    $root = Join-Path $env:LOCALAPPDATA 'CopilotZh\backups'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $root $stamp
    $filesDir = Join-Path $dir 'files'
    New-Item -ItemType Directory -Force -Path $filesDir | Out-Null

    $manifest = @()
    $idx = 0
    foreach ($it in @($Items)) {
        $idx++
        $backupPath = Join-Path $filesDir ('{0}-{1}' -f $idx, (Split-Path $it.Jar -Leaf))
        Copy-Item $it.Jar $backupPath -Force
        $manifest += [pscustomobject]@{
            product   = $it.Product
            pluginDir = $it.PluginDir
            jar       = $it.Jar
            backup    = $backupPath
            sha256    = (Get-Sha256 $it.Jar)
        }
    }

    $json = [pscustomobject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        items     = $manifest
    }
    $jsonText = $json | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), $jsonText, $script:Utf8NoBom)

    $restorePs1 = @'
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$json = [IO.File]::ReadAllText((Join-Path $dir 'manifest.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
foreach ($it in @($json.items)) {
    if (Test-Path $it.backup) {
        Copy-Item $it.backup $it.jar -Force
        Write-Host ("已恢复 " + $it.jar)
    } else {
        Write-Host ("备份文件缺失：" + $it.backup) -ForegroundColor Red
    }
}
Write-Host '恢复完成，请启动 IDE。'
'@
    [IO.File]::WriteAllText((Join-Path $dir 'restore.ps1'), $restorePs1, (New-Object System.Text.UTF8Encoding($true)))

    $restoreCmd = @"
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore.ps1"
pause
"@
    [IO.File]::WriteAllText((Join-Path $dir 'restore.cmd'), $restoreCmd, $script:Utf8NoBom)

    return $dir
}

function Restore-Backup {
    param([string]$Dir)
    $manifestPath = Join-Path $Dir 'manifest.json'
    if (-not (Test-Path $manifestPath)) { throw "找不到 manifest.json：$manifestPath" }
    $json = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($it in @($json.items)) {
        if (Test-Path $it.backup) {
            Copy-Item $it.backup $it.jar -Force
            Write-Log ("已恢复 " + $it.jar) 'Green'
        } else {
            Write-Log ("备份文件缺失：" + $it.backup) 'Red'
        }
    }
}

function Assert-IdeClosed {
    $running = @(Get-RunningIdes)
    if ($running.Count -gt 0 -and -not $IgnoreRunningIde) {
        Write-Log '检测到 JetBrains IDE 正在运行，请先完全关闭：' 'Red'
        foreach ($r in $running) { Write-Log ("  {0} (PID {1})" -f $r.Name, $r.Id) 'Red' }
        Write-Log '关闭后重新运行本脚本。' 'Yellow'
        exit 1
    }
}

# ---------------- main ----------------

Write-Host ''
Write-Host 'GitHub Copilot 汉化补丁 - 一键部署' -ForegroundColor Cyan
Write-Host ''

if ($DryRun -and $Restore) { throw '不能同时使用 -DryRun 和 -Restore' }

if ($Restore) {
    Assert-IdeClosed
    $root = Join-Path $env:LOCALAPPDATA 'CopilotZh\backups'
    $dir = $BackupDir
    if (-not $dir) {
        $latest = @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
        if ($latest.Count -eq 0) { throw '没有找到备份，请指定 -BackupDir' }
        $dir = $latest[0].FullName
    }
    Write-Log "从备份恢复：$dir" 'Cyan'
    Restore-Backup $dir
    Write-Log '恢复完成，请启动 IDE。' 'Green'
    exit 0
}

# 词条与菜单映射取自项目根目录，deploy 目录不再保留副本
$repoRoot = Split-Path $PSScriptRoot -Parent
$zhPath = Join-Path $repoRoot 'copilot.properties'
$menuPath = Join-Path $repoRoot 'zh.json'
if (-not (Test-Path $zhPath)) { throw "缺少词条文件：$zhPath（请在仓库目录内运行）" }
if (-not (Test-Path $menuPath)) { throw "缺少菜单文件：$menuPath（请在仓库目录内运行）" }

$translations = Load-Translations $zhPath
$menu = Load-Menu $menuPath
Write-Log ("词条：{0} 条；菜单映射：{1} 条" -f $translations.Count, $menu.Count)

if (-not $DryRun) { Assert-IdeClosed }

$pluginDirs = @(Get-PluginDirs)
if ($pluginDirs.Count -eq 0) {
    Write-Log '未找到 GitHub Copilot 插件。请确认已安装插件，或用 -PluginDir 指定目录。' 'Yellow'
    exit 1
}

$plans = @()
foreach ($pd in $pluginDirs) {
    $version = Get-PluginVersion $pd.Path
    $targets = @(Find-JarTargets $pd.Path)
    if ($targets.Count -eq 0) {
        Write-Log ("跳过 {0}：未找到可汉化的资源（插件版本 {1}）" -f $pd.Product, $version) 'Yellow'
        continue
    }

    $items = @()
    foreach ($t in $targets) {
        $replacements = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
        $propApplied = 0
        $menuApplied = 0
        $xmlEntry = $null
        if ($t.XmlEntries.Count -gt 0) { $xmlEntry = $t.XmlEntries[0] }

        $z = [IO.Compression.ZipFile]::OpenRead($t.Jar)
        try {
            if ($t.HasProperties) {
                $e = $z.GetEntry('copilot/copilot.properties')
                $sr = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
                $old = $sr.ReadToEnd()
                $sr.Close()
                $merged = Merge-Properties $old $translations
                if ($merged.Applied -gt 0 -and $merged.Text -ne $old) {
                    $replacements['copilot/copilot.properties'] = $merged.Text
                    $propApplied = $merged.Applied
                }
            }

            foreach ($xn in $t.XmlEntries) {
                $e = $z.GetEntry($xn)
                $sr = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
                $old = $sr.ReadToEnd()
                $sr.Close()
                $repl = Replace-MenuText $old $menu
                if ($repl.Count -gt 0 -and $repl.Text -ne $old) {
                    $replacements[$xn] = $repl.Text
                    $menuApplied += $repl.Count
                }
            }
        } finally { $z.Dispose() }

        if ($replacements.Count -gt 0) {
            $items += [pscustomobject]@{
                Product           = $pd.Product
                PluginDir         = $pd.Path
                Jar               = $t.Jar
                Replacements      = $replacements
                PropertiesApplied = $propApplied
                MenuApplied       = $menuApplied
                XmlEntry          = $xmlEntry
            }
        }
    }

    if ($items.Count -eq 0) {
        Write-Log ("跳过 {0}：已是汉化状态或译文未命中（插件版本 {1}）" -f $pd.Product, $version) 'Yellow'
        continue
    }
    $plans += [pscustomobject]@{ Product = $pd.Product; PluginDir = $pd.Path; Version = $version; Items = $items }
}

if ($plans.Count -eq 0) {
    Write-Log '没有需要处理的插件。' 'Yellow'
    exit 0
}

Write-Host ''
Write-Log '处理计划：' 'Cyan'
foreach ($p in $plans) {
    Write-Log ("  {0}  插件 {1}" -f $p.Product, $p.Version)
    foreach ($it in $p.Items) {
        Write-Log ("    {0}：词条 {1}，菜单 {2}" -f (Split-Path $it.Jar -Leaf), $it.PropertiesApplied, $it.MenuApplied)
    }
}

if ($DryRun) {
    Write-Host ''
    Write-Log 'DryRun：未写入任何文件。' 'Green'
    exit 0
}

if (-not $Yes) {
    $answer = Read-Host '确认写入以上 IDE？[Y/n]'
    if ($answer -and $answer -notmatch '^[Yy]') {
        Write-Log '已取消。' 'Yellow'
        exit 0
    }
}

$allItems = @()
foreach ($p in $plans) { foreach ($it in $p.Items) { $allItems += $it } }

$backupDir = New-Backup $allItems
$script:LogPath = Join-Path $backupDir 'install.log'
Write-Log ("备份目录：{0}" -f $backupDir) 'Gray'

$tempRoot = Join-Path $env:TEMP ('CopilotZh-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $idx = 0
    foreach ($it in $allItems) {
        $idx++
        $tmp = Join-Path $tempRoot ('{0}-{1}' -f $idx, (Split-Path $it.Jar -Leaf))

        $origKeys = 0
        $z = [IO.Compression.ZipFile]::OpenRead($it.Jar)
        try {
            $e = $z.GetEntry('copilot/copilot.properties')
            if ($e) {
                $sr = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
                $txt = $sr.ReadToEnd()
                $sr.Close()
                $origKeys = (Get-PropertiesKeys $txt).Count
            }
        } finally { $z.Dispose() }

        Repack-Jar $it.Jar $tmp $it.Replacements
        $v = Verify-Jar $tmp $it.XmlEntry $origKeys
        if (-not $v.Ok) { throw ("校验失败：{0} - {1}" -f $it.Jar, $v.Details) }

        $it | Add-Member -NotePropertyName TempJar -NotePropertyValue $tmp -Force
        Write-Log ("  已生成 {0}（{1}）" -f (Split-Path $it.Jar -Leaf), $v.Details)
    }

    foreach ($it in $allItems) {
        Copy-Item $it.TempJar $it.Jar -Force
        $h1 = Get-Sha256 $it.TempJar
        $h2 = Get-Sha256 $it.Jar
        if ($h1 -ne $h2) { throw ("安装后哈希不一致：{0}" -f $it.Jar) }
        Write-Log ("  已安装 {0}" -f (Split-Path $it.Jar -Leaf)) 'Green'
    }
} catch {
    Write-Log ("安装失败：{0}" -f $_.Exception.Message) 'Red'
    Write-Log '正在回滚...' 'Yellow'
    try {
        Restore-Backup $backupDir
        Write-Log '回滚完成。' 'Yellow'
    } catch {
        Write-Log ("回滚失败，请手动运行：{0}\restore.cmd" -f $backupDir) 'Red'
    }
    exit 1
} finally {
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Log '完成。请启动 IDEA 验证：Tools -> GitHub Copilot、Settings -> Tools -> GitHub Copilot。' 'Green'
Write-Log ("回滚：{0}\restore.cmd 或 deploy\install.cmd -Restore" -f $backupDir) 'Gray'
Write-Log '注意：插件自动更新会覆盖汉化，更新后重新运行本脚本即可。' 'Gray'
