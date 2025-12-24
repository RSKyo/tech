> Electron 是“当前最主流、最稳态”的桌面壳框架。  
> 短期、中期都不会被淘汰，反而已经进入“基础设施级”阶段。

## 一、Electron 在桌面壳领域是什么地位？

**一句话：事实标准（de facto standard）**

在“用 Web 技术做桌面 App”这个赛道里，Electron 的地位相当于：
- Web 后端里的 Spring Boot
- 前端里的 React
- 移动里的 Android SDK

**为什么？**

不是因为它“最先进”，而是因为：
1. 最早成熟
2. 被大量真实产品验证
3. 生态已经自循环

## 二、现实世界里，哪些主流 App 用的是 Electron？

你每天可能都在用，但没意识到：
- VS Code
- Slack
- Discord
- Notion
- Obsidian
- Postman
- Figma Desktop（早期 Electron，后逐步自研）

## Electron 世界里最重要的 3 个概念
### 1️⃣ 主进程（Main Process）

- **唯一**
- 拥有系统权限
- 能：
    - 执行 `.sh`
    - 读写文件
    - 打开系统文件选择器
    - 创建窗口

👉 类似“后台控制中心”

### 2️⃣ 渲染进程（Renderer Process）

- 就是你的“网页”
- 写 HTML / CSS / JS
- 负责 UI
- 不能直接执行 shell

👉 类似“前端页面”

### 3️⃣ 主进程 ↔ 渲染进程通信（IPC）

- UI 点按钮
- 发送消息给主进程
- 主进程执行脚本
- 把结果发回 UI

👉 这是 Electron 的核心模式

Electron 的最小 mental model（记住这个图）
```less
[ HTML / JS 页面 ]
       |
     (IPC)
       |
[ Electron 主进程 ]
       |
child_process.spawn
       |
[ 你的 .sh / ffmpeg ]
```
如果你理解了这条链路，Electron 就没什么神秘的。

