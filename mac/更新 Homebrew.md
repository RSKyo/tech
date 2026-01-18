Apple Silicon（大多数新机）路径是 `/opt/homebrew`，Intel 是 `/usr/local/Homebrew`。

按你的架构选一组命令：
**Apple Silicon:**
```bash
git -C /opt/homebrew fetch --force
git -C /opt/homebrew reset --hard origin/master
/opt/homebrew/bin/brew update --force --quiet
/opt/homebrew/bin/brew doctor
```
**Intel:**
```bash
git -C /usr/local/Homebrew fetch --force
git -C /usr/local/Homebrew reset --hard origin/master
/usr/local/bin/brew update --force --quiet
/usr/local/bin/brew doctor
```
### 💡 你现在需要做的其实很简单：

#### 1️⃣ 清理掉旧 tap（避免 update 再报错）：
```bash
/usr/local/bin/brew untap homebrew/services
```
#### 2️⃣ 更新主仓库与核心：
```bash
/usr/local/bin/brew update --force --quiet
/usr/local/bin/brew doctor
```
（这次不会再去找 `homebrew-services.git` 了 ✅）
#### 3️⃣ 然后继续装 bash：
```bash
/usr/local/bin/brew install bash
```
#### 4️⃣ 验证：
```bash
/usr/local/bin/bash --version
```
看到 `GNU bash, version 5.x.x` 就表示成功。
# 备用方案（不依赖 brew）

**Conda/Mamba 安装 bash：**
```bash
conda install -c conda-forge bash
# 然后用：
~/miniconda3/bin/bash your_script.sh args...
```
**MacPorts：** `sudo port install bash`（如果你已经在用 MacPorts）