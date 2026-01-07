<div style="display: flex; justify-content: center; align-items: center;">
  <a href="https://www.jetbrains.com/zh-cn"><img src="https://github.com/devicons/devicon/blob/master/icons/jetbrains/jetbrains-original.svg" title="JetBrains" alt="JetBrains" width="55" height="55"/></a>
  <a href="https://plugins.jetbrains.com/plugin/17718-github-copilot"><img src="pluginIcon.svg" title="GitHub Copilot 插件" alt="Copilot" width="55" height="55"/></a>
  <img src="zh.svg" title="简体中文"  alt="Chinese" width="55" height="55"/>
</div>

# JetBrains GitHub Copilot 插件汉化补丁

JetBrains 系 GitHub Copilot 插件自制汉化包，旨在为 JetBrains 开发工具提供更好的中文支持，提升用户体验。

## 汉化效果
![汉化示例](https://github.com/user-attachments/assets/7ef41df6-e609-45d4-aca4-302aabfb95a3)


1. 使用方法
2. 安装指南
3. 使用说明
4. 贡献指南
5. 许可证

### 使用方法

1. 从发行版下载对应版本的插件包（已汉化好
2. 打开 JetBrains 系 IDE，点击右上角齿轮图标 ---> “已安装”右侧齿轮 ---> 从磁盘安装插件，选择刚下载的压缩包即可。

### 在本地汉化

首先你需要安装 Python

1. 克隆仓库：
   
    ```
    git clone https://github.com/TC999/jetbrains-copilot-chinese.git
    ```
    
3. 进入项目目录：
   
    ```
    cd jetbrains-copilot-chinese
    ```
    
4. 安装依赖：
   
    ```
    pip install -r requirements.txt
    ```
    
5. 从[JetBrains插件市场](https://plugins.jetbrains.com/plugin/17718-github-copilot/versions)下载原版插件包
6. 打开压缩包，并将其中的`lib/core.jar`解压到项目根目录
7. 解压`core.jar`所有内容到`core`文件夹下（右键选择“解压到`core`”)
8. 直接替换：运行`2.replace.py`即可，无需运行`1.extract.py`（提取源词条的脚本
9. 将根目录`copilot.properties`替换到`core/copilot`下，将`core`中所有的文件直接塞回`core.jar`，再将其塞回原版插件包，汉化成功

### GitHub Actions（推荐
1. 复刻此仓库
2. 允许运行工作流程
3. 打开[JetBrains插件市场](https://plugins.jetbrains.com/plugin/17718-github-copilot/versions)，找到对应版本点击下载，复制下载时显示的链接，然后这样修改

原链接

```
https://downloads.marketplace.jetbrains.com/files/17718/654597/github-copilot-intellij-1.5.30-242.zip?updateId=654597&pluginId=17718&family=INTELLIJ
```

删除`zip`后面的所有参数，示例
```
https://downloads.marketplace.jetbrains.com/files/17718/654597/github-copilot-intellij-1.5.30-242.zip
```

在 Actions 页面点击运行工作流程，分别填入“文件下载链接”、“发行版标签”、“发行版标题”，点击运行即可（需提前设置 Actions 写入仓库权限）

### 贡献指南
欢迎任何形式的贡献！您可以通过以下方式参与：
1. 提交 Issue 描述问题或建议。
2. Fork 仓库并提交 Pull Request。

### 许可证
本项目采用 MIT 许可证，详细信息请参见 [LICENSE](LICENSE) 文件。
