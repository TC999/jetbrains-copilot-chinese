# 一键部署（Windows x64）

自动扫描本机所有 JetBrains IDE 的 GitHub Copilot 插件，备份后写入中文资源。

## 使用

1. 完全关闭所有 JetBrains IDE（IntelliJ、PyCharm、WebStorm、GoLand 等）
2. 双击 `install.cmd`
3. 确认处理计划，等待完成
4. 启动 IDE

也可以从命令行运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

## 参数

| 参数 | 说明 |
|---|---|
| `-DryRun` | 只检测和预览，不写文件 |
| `-Restore` | 恢复最近一次备份 |
| `-BackupDir <路径>` | 配合 `-Restore` 指定备份目录 |
| `-PluginDir <路径>` | 手动指定 `github-copilot-intellij` 插件目录 |
| `-Ide <名称>` | 只处理名称包含该字符串的 IDE，如 `IntelliJIdea` |
| `-Yes` | 跳过确认 |
| `-IgnoreRunningIde` | 忽略运行中的 IDE（仅供测试） |

示例：

```powershell
# 预览
.\install.ps1 -DryRun

# 只处理 IntelliJ
.\install.ps1 -Ide IntelliJIdea

# 回滚
.\install.ps1 -Restore
```

## 兼容性

- Windows 10/11 x64，PowerShell 5.1+
- 同时兼容旧版 `lib/core.jar` 和新版 `lib/modules/*.jar` 结构
- 以已安装插件的资源文件为底合并译文，不会丢失新版新增键
- 新版新增的、词条表里没有的文案保持英文
- 插件自动更新会覆盖汉化，更新后重新运行即可

## 备份与回滚

每次安装会在 `%LOCALAPPDATA%\CopilotZh\backups\<时间戳>\` 生成：

- `files\`：原版 jar
- `manifest.json`：文件路径与 SHA256
- `restore.ps1` / `restore.cmd`：独立回滚脚本

也可以运行 `install.cmd -Restore` 恢复最近一次备份。

## 数据文件

脚本从项目根目录读取翻译数据，`deploy` 目录下不放副本：

- `../copilot.properties`：1168 条词条（仓库原有 314 条 + 适配 1.21.1 新增 854 条），在 1.21.1 上实际命中 1094 条
- `../zh.json`：47 条菜单映射（含 `...` / `…` 变体），在 1.21.1 上替换 25 个菜单项 + 6 个动作文本

因此脚本需要和项目根目录保持原有结构；单独拷走 `deploy` 目录会因缺少这两个文件而报错（`-Restore` 不需要它们）。

只修改插件里的文本资源，不改变插件逻辑。
