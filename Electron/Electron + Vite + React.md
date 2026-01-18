## 你需要掌握的“最少知识”

- **Vite**：把 React 页面跑起来（开发服务器 + 打包）
    
- **Electron**：打开一个窗口，把 Vite 页面加载进去
    
- **IPC**：React 点按钮 → Electron 执行系统能力（选文件 / 运行 `.sh`）→ 把输出回传
    

你不需要先学：

- 打包上架
    
- 自动更新
    
- App Store
    
- 高级安全模型（先用默认安全做法即可）
    

---

# 入门路线（4 步，强烈建议按顺序做）

## Step 0：准备环境（一次性）

在终端确认：

`node -v npm -v`

如果没有 Node（macOS 最常见）：

`brew install node`

---

## Step 1：先学 Vite（只跑网页，不碰 Electron）

目标：**10 分钟内看到一个 React 页面**。

`mkdir my-tool cd my-tool npm create vite@latest`

交互时选：

- Framework：**React**
    
- Variant：**JavaScript**
    

然后：

`cd <项目名> npm install npm run dev`

浏览器打开提示的地址（通常是 `http://localhost:5173`）。  
能看到页面 = Vite 入门完成。

你在这一关需要理解的只有一句话：

> Vite = 本地开发服务器 + 构建工具

---

## Step 2：加 Electron（只打开窗口加载页面，不做 IPC）

目标：**同一个 React 页面，出现在桌面窗口里**。

在项目里装 Electron：

`npm i -D electron`

新建 `electron/main.cjs`：

`const { app, BrowserWindow } = require("electron");  const isDev = !app.isPackaged;  function createWindow() {   const win = new BrowserWindow({ width: 1000, height: 700 });    if (isDev) {     win.loadURL("http://127.0.0.1:5173");   } }  app.whenReady().then(createWindow);`

然后在 `package.json` 加：

`{   "main": "electron/main.cjs",   "scripts": {     "dev": "vite",     "electron": "electron ."   } }`

运行：

1. 一个终端：
    

`npm run dev`

2. 另一个终端：
    

`npm run electron`

此时你会看到一个桌面窗口显示 React 页面。  
这一步完成 = Electron 入门完成 60%。

你需要理解的只有两句：

- Electron 主进程负责创建窗口
    
- 窗口里加载的是网页（开发时就是 Vite 地址）
    

---

## Step 3：加“安全桥”（preload）让 React 能调用系统能力（IPC）

目标：React 能点击按钮触发 Electron 主进程返回数据（先返回固定字符串）。

新建 `electron/preload.cjs`：

`const { contextBridge, ipcRenderer } = require("electron");  contextBridge.exposeInMainWorld("api", {   ping: () => ipcRenderer.invoke("app:ping"), });`

修改 `electron/main.cjs`（加 webPreferences + ipcMain）：

`const { app, BrowserWindow, ipcMain } = require("electron"); const path = require("path");  const isDev = !app.isPackaged;  function createWindow() {   const win = new BrowserWindow({     width: 1000,     height: 700,     webPreferences: {       preload: path.join(__dirname, "preload.cjs"),       contextIsolation: true,       nodeIntegration: false,     },   });    if (isDev) win.loadURL("http://127.0.0.1:5173"); }  ipcMain.handle("app:ping", async () => {   return { ok: true, msg: "pong from main process" }; });  app.whenReady().then(createWindow);`

在 `src/App.jsx` 里加一个按钮：

`function App() {   async function onPing() {     const res = await window.api.ping();     alert(JSON.stringify(res));   }    return (     <div>       <button onClick={onPing}>Ping Main</button>     </div>   ); }  export default App;`

重启两个进程后，点按钮弹出 `pong`。  
这一步完成 = 你已经掌握 Electron 的核心模式（UI ↔ 系统能力）。

---

## Step 4：把 “pong” 换成 “执行你的 sh”

目标：点按钮执行 `media_segment_plan.sh`，把 stdout/stderr 显示出来。

这一步我建议你先用一个最简单脚本验证：

`echo 'echo hello; echo err >&2' > /tmp/test.sh chmod +x /tmp/test.sh`

然后在主进程用 `child_process.spawn` 执行并返回 stdout/stderr。  
等这一步通了，再接入你的真实脚本和参数。

---

# 你现在该从哪里开始？

你说你没用过 Electron、Vite，所以最稳的做法是：

- **先 Step 1：Vite 跑起来**
    
- **再 Step 2：Electron 窗口能加载 Vite 页面**
    
- **再 Step 3：React 能通过 IPC 调到主进程**
    

你只要把前三步走通，第四步（执行 sh）就是“替换 ping 的实现”，非常自然。

---

## 我建议你现在就做一件事

按 Step 1 创建 Vite React 项目，并把你终端输出的：

- 项目结构
    
- `npm run dev` 是否成功、地址是什么
    

贴出来（只要粘贴终端输出即可）。  
我就按你的实际输出，继续给你“下一步最短指令”，确保你不踩坑。