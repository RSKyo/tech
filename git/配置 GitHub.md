## 配置全局的 user.name 和 user.email

如果你要推送到 GitHub，最好填写你 GitHub 账号的名字和邮箱，因为 GitHub 会根据邮箱来识别 commit 属主。
```bash
git config --global user.name "你的名字"
git config --global user.email "你的邮箱@example.com"
```
GitHub 邮箱通常是：
- 你注册 GitHub 时用的邮箱，或
- GitHub 提供的 **no-reply 隐私邮箱**（如果你启用了 email privacy）

你可以在这里查看自己的邮箱：  
GitHub → Settings → Emails

也可以随便写一个（不推荐），Git 完全允许你写任意名字和邮箱，只是：
- GitHub 不会把提交和你的账号关联
- 看起来不专业
- 将来查看 commit 作者会混乱

想保护隐私？用 GitHub 的 no-reply 邮箱！
GitHub 每个用户都有一个类似：
```css
12345678+你的用户名@users.noreply.github.com
```
你可以选择这个邮箱，这样：
- GitHub 能识别你的提交
- 又不会泄露真实邮箱

## push 代码
push 代码到 GitHub 有两种方式，**HTTPS 方式** 和 **SSH 方式**。

### 方式1、HTTPS（需要 PAT Token）
当终端问你：
```bash
Username for 'https://github.com':
```
你输入：**你的 GitHub 用户名**
然后它会问：
```bash
Password for 'https://github.com':
```
这里不能输入密码，**必须是你 GitHub 的 PAT Token**。
如果你没有 Token → 去创建：
GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** 或 **Classic tokens**
Classic token 最简单：  
勾选：
- repo（必须）
- workflow（可选）
- read:user（可选）
生成后复制 Token → 在 “Password” 那里粘贴。

### 方式二、SSH（最推荐，不必每次输入密码）
1、检查你这台 Mac 是否已有 SSH key
```bash
ls -al ~/.ssh
```
如果能看到类似：
```rust
id_ed25519
id_ed25519.pub
```
说明已有 key。  
如果没有，我们就生成一个。
```bash
ssh-keygen -t ed25519 -C "你GitHub邮箱"
```
一路回车即可。
生成后，查看公钥：
```bash
cat ~/.ssh/id_ed25519.pub
```
复制整段内容。
2、把公钥加到 GitHub
GitHub → Settings → SSH and GPG keys → New SSH key  
Title 随便填，比如 “Mac mini 2025”  
Key 粘贴刚才的 id_ed25519.pub
保存。
3、测试是否配置成功
```bash
ssh -T git@github.com
```
成功会看到：
```bash
Hi xxx! You've successfully authenticated...
```
4、把你的本地仓库改为 SSH URL
查看本地仓库的连接状态：
```shell
git remote -v
```
你会看到类似：
```shell
origin  https://github.com/你的用户名/xxx.git (fetch)
origin  https://github.com/你的用户名/xxx.git (push)
```
或者：
```shell
origin  git@github.com:你的用户名/xxx.git (fetch)
origin  git@github.com:你的用户名/xxx.git (push)
```
只会是其中一种，不会同时存在。
如果是 HTTPS 的方式，则改为 SSH：
```bash
git remote set-url origin git@github.com:你的用户名/xxx.git
```
5、克隆远程仓库：
```shell
git clone git@github.com:你的用户名/xxx.git
```