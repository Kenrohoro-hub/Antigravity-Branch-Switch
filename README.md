# Antigravity Branch Switch

Antigravity 桌面版对话分支开关工具 / Conversation branching flag switch for Antigravity Desktop.

## 中文

一个 Windows 便携脚本，用于启用 Antigravity 桌面版隐藏的两个实验开关：**对话分支**和**从历史消息处分叉**。不是编辑器插件，不修改应用安装包。

### 使用方法

1. 下载并解压整个仓库，打开 Antigravity 桌面版，等待加载完成，只保留一个主窗口。
2. 双击 **`启动Start.cmd`**，保存原值并启用开关。
3. 回到应用，检查对话菜单是否出现 **Fork**；启用开关不保证菜单或功能可用。

| 文件 | 用途 |
| --- | --- |
| `启动Start.cmd` | 保存原值并启用分支开关 |
| `check-status.cmd` | 只查看当前状态，不修改开关 |
| `restore.cmd` | 恢复本工具保存的原值，保留其他开关 |

### 前提与特点

- Windows 10/11、系统自带的 Windows PowerShell 5.1；无需 Node.js、PowerShell 7、管理员权限或下载依赖。
- 应用须已提供本机调试接口，使用当前用户的默认配置目录；不支持旧版 IDE 或自定义用户数据目录。
- 整个文件夹可以复制到其他电脑，支持中文和空格路径，自动识别本机端口。
- 窗口跟随 Windows 显示语言：简体中文显示中文，其他语言显示英文。系统原始错误保留系统语言。
- 原值保存在当前应用的本地存储中；重复启用不会覆盖备份，成功恢复后移除备份。不会把聊天、账号或调试地址写入工具文件夹。
- 仅连接本机并核对进程归属；不创建对话、不发送消息、不调用模型，也不修改系统的永久执行策略。

**验证范围：** 已在 Antigravity 2.28.2 上验证 PowerShell 5.1 只读连接、中文/英文状态显示及中文路径启动；开关启用和恢复逻辑通过模拟存储测试。**实际菜单显示、分叉创建及重启后保持尚未验证；应用更新可能使工具失效。**

## English

A portable Windows script that enables two hidden experimental flags in Antigravity Desktop: **conversation branching** and **forking at a historical step**. It is not an editor extension and does not patch the app installation.

### Quick start

1. Download and extract the entire repository. Open Antigravity Desktop, wait for it to load, and keep only one main window open.
2. Double-click **`启动Start.cmd`** to save the original values and enable the flags.
3. Return to the app and check the conversation menu for **Fork**. Enabling the flags does not guarantee that the menu or feature is available.

| File | Purpose |
| --- | --- |
| `启动Start.cmd` | Save original values and enable branching flags |
| `check-status.cmd` | Read status without changing flags |
| `restore.cmd` | Restore saved original values while preserving other flags |

### Requirements and features

- Windows 10/11 with built-in Windows PowerShell 5.1. No Node.js, PowerShell 7, administrator privileges, or dependency downloads required.
- The running app must expose its local debugging interface and use the current user's default profile. The older IDE and custom user-data directories are not supported.
- Copy the whole folder to move it to another PC. Chinese characters and spaces in paths are supported; local ports are detected automatically.
- The window follows the Windows display language: Chinese for Simplified Chinese, English for all other languages. Native system errors retain their original language.
- Original values stay in the app's local storage. Repeated activation preserves the first backup; successful restoration removes it. No chats, account data, or debugging addresses are saved in the tool folder.
- Connects only to the local app and checks process ownership. Does not create conversations, send messages, call models, or permanently change system execution policy.

**Validation:** PowerShell 5.1 read-only connectivity, Chinese/English status output, and Chinese-path launch were verified with Antigravity 2.28.2. Flag enable/restore logic passed simulated-storage tests. **Actual menu visibility, conversation forking, and persistence after restarting remain unverified. App updates may break this tool.**

## 开发测试 / Development tests

```text
node --test branch-switch.test.mjs
```

Node.js 仅用于开发测试，日常使用不需要。 / Node.js is needed only for development tests, not for normal use.
