# yt-dlp

`yt-dlp` 是一个命令行工具，用于从各种视频网站（如 YouTube、Bilibili、Twitter、TikTok 等）下载视频、音频和字幕。它是知名工具 `youtube-dl` 的一个功能更强、更新更频繁的分支（fork），社区非常活跃。

## 核心特点

- **支持网站广泛**：除了 YouTube，还支持数千个视频网站。
- **格式灵活**：可下载不同清晰度（360p、720p、1080p、4K）的视频，也能单独提取音频（如 mp3、m4a）。
- **字幕功能**：支持下载字幕、自动生成字幕、字幕翻译。
- **强大的参数**：支持断点续传、代理、cookies 登录、过滤下载条件（如按时长、清晰度等）。    
- **持续更新**：社区频繁维护，能快速支持新的网站和修复兼容性问题。

## 安装方法

### 1. 安装 / 确认 Python（下载最新的版本）

去官网装最新版（.pkg 安装包）：  [https://www.python.org/downloads/macos/](https://www.python.org/downloads/macos/)
安装完后，打开终端验证：
```bash
python3 --version
pip3 --version
```
如果这里还是显示 3.7.x，说明你的 shell 走的是系统旧 Python。  
这时先确保 `/usr/local/bin` 在 PATH 前面（把它放到最前面）：
```bash
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
hash -r
python3 --version
```
官方 Python for macOS 自带了一个证书安装脚本：
```bash
/Applications/Python\ 3.13/Install\ Certificates.command
```
- 找到你装的 Python 版本目录（比如 `Python 3.13`），双击运行里面的 `Install Certificates.command`。
- 或者直接在终端执行上面的命令。
- 这会把 macOS 系统钥匙串的证书同步给 Python，用于 SSL 验证。

### 2. 升级 pip / setuptools / wheel

作用：让包管理更稳，避免因为旧版工具链导致的安装报错。
```bash
python3 -m ensurepip --upgrade
python3 -m pip install -U pip setuptools wheel
```

### 3. 安装 / 升级 yt-dlp

正常情况下，用新装的 Python 直接安装即可（无需 sudo）。
```bash
python3 -m pip install -U yt-dlp
```
安装完成后，先用“模块方式”确认（不依赖 PATH，最准）：
```bash
python3 -m yt_dlp --version
```

### 4. 让 `yt-dlp` 命令行可直接使用（处理 PATH）

大多数时候，上一步装好后就能直接用 `yt-dlp`。  
如果提示 `command not found`，通常是命令安装在“用户脚本目录”里但 PATH 没包含。
自动探测并加入 PATH（推荐）
```bash
# 取出 pip 的用户脚本目录（--user 时一定用到；有时全局装也会用到）
BIN_DIR=$(python3 - <<'PY'
import site, os
print(os.path.join(site.USER_BASE, "bin"))
PY
)
echo "User scripts in: $BIN_DIR"

# 写入 ~/.zshrc（永久生效；若已有就不重复写）
grep -Fq "$BIN_DIR" ~/.zshrc || echo "export PATH=\"$BIN_DIR:\$PATH\"" >> ~/.zshrc

# 让当前会话立刻生效
source ~/.zshrc
hash -r
```
常见的用户脚本目录路径：
- `~/Library/Python/3.13/bin`
- 有些环境还会用到 `~/.local/bin`（你也可以一并加入 PATH）

### 5. 验证安装是否成功

```bash
# 看解析到的是哪个可执行文件
which -a yt-dlp || true

# 直接运行命令版
yt-dlp --version

# 兜底验证（不依赖 PATH）
python3 -m yt_dlp --version
```
期望效果：两者都能输出版本号（例如 2024/2025 年的版本）。

### 6. 常见问题排查（遇到再看）

A. `Permission denied`（权限不足）
说明向全局目录写入失败。直接改用 **用户安装**：
```bash
python3 -m pip install -U --user yt-dlp
# 之后务必执行上面的「第 4 步」把 BIN_DIR 加入 PATH
```

B. `yt-dlp: command not found`
- 先跑：`python3 -m yt_dlp --version` 确认已安装；
- 再按「第 4 步」把 `BIN_DIR`（例如 `~/Library/Python/3.13/bin`）写进 PATH；
- 重新 `source ~/.zshrc && hash -r`，再试 `yt-dlp --version`。

C. 一直跑到旧的 Python 3.7
- 用 `type -a python3` 查看解析顺序；
- 确保 `/usr/local/bin` 在 `/usr/bin` 之前（见“0.先安装/确认 Python”里的 PATH 调整）；
- 检查是否有 alias 抢优先级：
```bash
alias | grep -E 'python3|pip3'
```
如果有 `alias python3='/usr/bin/python3'`，删掉它（从 `~/.zshrc` 注释/移除），然后：
```bash
source ~/.zshrc
hash -r
```

D. 看到 `NotOpenSSLWarning`（SSL 警告）
- 这是旧系统 Python（LibreSSL）常见的提示；
- 升级到官方 Python 3.13+ 并确保 `python3` 指向它，警告就会消失；
- 再执行一次：
```bash
python3 -m pip install -U pip yt-dlp
```

### 7. 小抄：一条龙执行（复制即用）

默认尝试“正常安装”；若你权限受限导致失败，请改用 `--user`（第 6A 条）。
```bash
# 确保用的是新 Python
python3 --version

# 升级工具链
python3 -m ensurepip --upgrade
python3 -m pip install -U pip setuptools wheel

# 安装/升级 yt-dlp
python3 -m pip install -U yt-dlp

# 如提示找不到命令，则加入用户脚本目录到 PATH
BIN_DIR=$(python3 - <<'PY'
import site, os
print(os.path.join(site.USER_BASE, "bin"))
PY
)
grep -Fq "$BIN_DIR" ~/.zshrc || echo "export PATH=\"$BIN_DIR:\$PATH\"" >> ~/.zshrc
source ~/.zshrc
hash -r

# 验证
which -a yt-dlp || true
yt-dlp --version
python3 -m yt_dlp --version
```

## yt-dlp 常见命令速查表

### 基础下载

**下载视频**
```bash
yt-dlp URL
```

**选择最佳质量（视频+音频合并）**
```bash
yt-dlp -f "bestvideo+bestaudio" URL
```

**指定清晰度（例如 720p）**
```bash
yt-dlp -f "bestvideo[height=720]+bestaudio" URL
```

最佳画质 + 字幕
`-N 8` → 开 8 个线程同时下载
```bash
yt-dlp -N 8 \
  -f "bv*+ba/b" \
  --write-subs --write-auto-subs --sub-langs "zh-Hans,zh-Hant,zh-CN,zh-TW,zh-HK,zh" \
  --convert-subs srt --embed-subs \
  -o "~/Downloads/%(title)s [%(resolution)s].%(ext)s" \
  URL
```

### 音频下载

仅下载音频（默认格式）
```bash
yt-dlp -x URL
```

转换为 MP3
```bash
yt-dlp -x --audio-format mp3 URL
```

保持原始音频格式
```bash
yt-dlp -f bestaudio URL
```

### 字幕

下载字幕（不下载视频）
```bash
yt-dlp --write-subs --skip-download URL
```

下载中文字幕
```bash
yt-dlp --write-subs --sub-lang zh --skip-download URL
```

下载自动生成字幕
```bash
yt-dlp --write-auto-subs --sub-lang en URL
```

### 批量与播放列表

下载整个播放列表
```bash
yt-dlp PLAYLIST_URL
```

从文件批量下载
```bash
yt-dlp -a urls.txt
```
（`urls.txt` 每行一个视频链接）

### 下载设置

自定义文件名
```bash
yt-dlp -o "%(title)s.%(ext)s" URL
```

限制下载速度（500 KB/s）
```bash
yt-dlp --limit-rate 500K URL
```

断点续传（默认支持）
```bash
yt-dlp -c URL
```

### 进阶技巧

只下载视频的前 60 秒
```bash
yt-dlp --download-sections "*0-60" URL
```

**使用 cookies 登录**（适合 Bilibili、会员视频等）
```bash
yt-dlp --cookies cookies.txt URL
```

显示所有可用格式
```bash
yt-dlp -F URL
```

小提示：第一次用时，可以先加上 `-F` 查看视频的所有可用格式，再用 `-f` 精准选择。

### 示例

**最佳画质 + 字幕**

```bash
yt-dlp -N 8 --cookies-from-browser chrome \
  -f "bv*+ba/b" \
  --write-subs --write-auto-subs --sub-langs "zh-Hans,zh-Hant,zh-CN,zh-TW,zh-HK,zh" \
  --convert-subs srt --embed-subs \
  -o "%(title)s [%(resolution)s] [%(id)s].%(ext)s" \
  URL
```
- 多线程下载（更快）：`-N 8`（或 16）
- 限速：`--limit-rate 2M`（每秒 2MB）
- **需要登录/地区解锁时**（直接用已登录的浏览器 Cookies）：
	- Safari：`--cookies-from-browser safari`
	- Chrome：`--cookies-from-browser chrome`
	- Edge：`--cookies-from-browser edge`
- `-f "bv*+ba/b"`：优先下载 **bestvideo + bestaudio**；如果平台只提供合并流就退回 `best`。
- `--write-subs --write-auto-subs`：先尝试“人工字幕”，没有再尝试“自动生成字幕”。
- `--sub-langs "...,zh"`：把常见中文轨道都列上（简体/繁体/地区码/泛 zh）。
- `--convert-subs srt`：下载后把字幕转成 **SRT**（通用）。
- `--embed-subs`：把字幕直接“嵌入”到视频文件里（同时也会保留外置字幕文件）。
- `-o ...`：输出文件名包含分辨率和视频 ID，便于区分。

**转为** .mp4

如果你想最终一定是 **.mp4**（方便在某些设备上播放），用下面这条；可能牺牲一点点码率（因为会挑选 mp4/m4a 流）。
```bash
yt-dlp -f "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" \
  --merge-output-format mp4 \
  --write-subs --write-auto-subs --sub-langs "zh-Hans,zh-Hant,zh-CN,zh-TW,zh-HK,zh" \
  --convert-subs srt --embed-subs \
  -o "%(title)s [%(resolution)s] [%(id)s].mp4" \
  URL
```