## 更新 Bash
macOS 自带 Bash 3.2 太老了，安装 Bash 5 即可解决所有语法问题。
```bash
brew install bash
```
安装后新 bash 一般位于：
```bash
/opt/homebrew/bin/bash
```
检查：
```bash
/opt/homebrew/bin/bash --version
```

## 防止睡眠
```bash
caffeinate -d
```