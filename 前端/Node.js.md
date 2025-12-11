## 什么是 nvm

nvm (Node Version Manager，Node 版本管理器) 是一个开源项目，它的官方仓库在 GitHub 上：
```text
https://github.com/nvm-sh/nvm
```

在这个仓库里，有一个文件叫 `install.sh`，它是安装 nvm 的官方脚本，里面写的是：
- 创建 `~/.nvm` 目录
- 下载 nvm 本体
- 修改你的 `~/.bashrc` / `~/.zshrc`
- 把 nvm 加入 PATH

到 GitHub Releases（推荐）查看最新版本：
```text
https://github.com/nvm-sh/nvm/releases
```

查看当前安装的版本：
```shell
nvm -v
```

## 安装 nvm

通过 nvm 的官方脚本安装：
```shell
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
```
这条命令会：
- 从 GitHub 下载 `nvm` 安装脚本；
- 并用 `bash` 执行它；
- 结果是在你用户目录下创建并配置 NVM（一般在 `~/.nvm` 中）。

然后执行：
```shell
source ~/.zshrc（需要看当前 shell 是哪个）
```
`install.sh` 只是改了文件，不会反向影响你已经打开的这个 shell 进程，所以，安装完成后，当前窗口里 `nvm` 可能还不存在。
- 当前 shell 是 **zsh** → `source ~/.zshrc`
- 当前 shell 是 **bash** → `source ~/.bashrc` 或 `source ~/.bash_profile`

更新本地版本只需要安装最新版覆盖即可。

## 安装 node

查看最新的 Node.js LTS（长期支持）版本：
