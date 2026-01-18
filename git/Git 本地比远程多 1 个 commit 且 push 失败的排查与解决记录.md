> 适用场景：  
> `git status` 提示分支领先远程，例如：  
> `Your branch is ahead of 'origin/main' by 1 commit.`  
> 但执行 `git push` 时失败（HTTP 400 / remote hung up 等）。

---

## 0. 问题现象

### 0.1 `git status` 提示本地领先远程

命令：

    git status

典型输出：

    On branch main
    Your branch is ahead of 'origin/main' by 1 commit.
      (use "git push" to publish your local commits)
    nothing to commit, working tree clean

含义：

- 当前分支：`main`（本地分支）
- 远程分支：`origin/main`（远程仓库 `origin` 上的 `main`）
- `ahead by 1 commit`：本地多了 1 次提交还没同步到远程

即：**commit 成功，但 push 没成功**。

---

### 0.2 使用 HTTPS push 时的错误

命令：

    git push
    # 或
    git push origin main

错误示例：

    Enumerating objects: 43, done.
    Counting objects: 100% (43/43), done.
    Delta compression using up to 16 threads
    Compressing objects: 100% (36/36), done.
    error: RPC failed; HTTP 400 curl 22 The requested URL returned error: 400
    fatal: the remote end hung up unexpectedly
    Writing objects: 100% (37/37), 14.16 MiB | 14.66 MiB/s, done.
    Total 37 (delta 1), reused 0 (delta 0)
    fatal: the remote end hung up unexpectedly

说明：  
本地已经把数据打包并开始发送，但在 HTTP 层被 400 错误和断连打断，**远程没更新**。

---

## 1. 基础概念：本地分支 vs 远程分支

- `main`：本地当前分支。
- `origin`：远程仓库的名字（默认代表 GitHub 上的那个仓库）。
- `origin/main`：远程仓库 `origin` 里的 `main` 分支。

关系示意：

    本地 main   <—— 对应 ——>   远程 origin/main

`Your branch is ahead of 'origin/main' by 1 commit.`  
= 本地 `main` 比远程 `origin/main` 多 1 个提交。

---

## 2. 初步排查命令

### 2.1 查看当前状态

    git status

用途：  
- 看当前在哪个分支；
- 确认是否领先 / 落后远程；
- 是否还有未提交改动。

---

### 2.2 查看远程地址是否正确

    git remote -v

示例输出（HTTPS）：

    origin  https://github.com/RSKyo/study.git (fetch)
    origin  https://github.com/RSKyo/study.git (push)

说明当前 push/pull 走的是 HTTPS 通道。

---

### 2.3 检查远程仓库是否可访问

    git ls-remote origin

示例输出：

    d6dfead3500e3255ba19f2750c28602ebe025d55    HEAD
    d6dfead3500e3255ba19f2750c28602ebe025d55    refs/heads/main

说明：  
- 远程仓库存在且可访问；  
- 认证没问题；  
- 真正的问题在于 **HTTPS 推送链路**。

---

## 3. 解决思路：从 HTTPS 换到 SSH

由于 HTTPS push 经常被网络 / 代理搞崩，  
最稳定的长期方案是：**配置 SSH key，将远程 URL 改为 SSH，再用 SSH 推送。**

主要步骤：

1. 检查 / 生成本地 SSH key。  
2. 把公钥添加到 GitHub。  
3. （如有）解决 `REMOTE HOST IDENTIFICATION HAS CHANGED` 警告。  
4. 把远程地址从 HTTPS 改成 SSH。  
5. 用 SSH 测试与 GitHub 的连接。  
6. 再次 `git push origin main`。

---

## 4. SSH 详细配置步骤

### 4.1 检查本地是否已存在 SSH key

    ls ~/.ssh

如果里面已经有类似：

    id_ed25519
    id_ed25519.pub

说明你已有一对 SSH key，可以直接用，不一定要重新生成。

---

### 4.2 如需生成新的 SSH key

    ssh-keygen -t ed25519 -C "你的 GitHub 邮箱"

交互说明：

- 提示保存路径时直接回车使用默认：`~/.ssh/id_ed25519`
- 是否设置密码（passphrase）可根据需要选择：  
  不设就直接回车；设的话输入两遍同样字符串即可。

生成后会得到：

- 私钥：`~/.ssh/id_ed25519`
- 公钥：`~/.ssh/id_ed25519.pub`

---

### 4.3 将公钥添加到 GitHub

1. 终端输出公钥内容：

       cat ~/.ssh/id_ed25519.pub

2. 复制这整一行文本（从 `ssh-ed25519` 开始到邮箱结束）。

3. 打开 GitHub → 右上角头像 → Settings → SSH and GPG keys → New SSH key

4. 填写：
   - Title：随便起（如 `MacBook` / `zhmbp`）
   - Key：粘贴刚才复制的公钥内容

5. 点击 **Add SSH key** 保存。

---

### 4.4 如果出现 “REMOTE HOST IDENTIFICATION HAS CHANGED!” 警告

错误示例：

    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    Host key for github.com has changed and you have requested strict checking.
    Host key verification failed.

原因：  
本地缓存的 GitHub 服务器指纹和当前不一致（可能是 GitHub 更新了 host key，或你改了网络 / 重装系统等）。

解决办法：

1. 删除本地 `known_hosts` 中旧的 GitHub 记录：

       ssh-keygen -R github.com

   会提示类似：

       # Host github.com found: line 1
       /Users/xxx/.ssh/known_hosts updated.
       Original contents retained as /Users/xxx/.ssh/known_hosts.old

2. 之后重新测试连接（见下一小节），会再次询问是否信任新的 GitHub host key。

---

### 4.5 测试 SSH 是否能连上 GitHub

    ssh -T git@github.com

第一次执行会出现：

    The authenticity of host 'github.com (140.82.xx.xx)' can't be established.
    ED25519 key fingerprint is SHA256:xxxx...
    Are you sure you want to continue connecting (yes/no/[fingerprint])?

输入：

    yes

如果 SSH key 和 GitHub 配置正常，会看到：

    Hi RSKyo! You've successfully authenticated, but GitHub does not provide shell access.

这就表示：**SSH 认证成功，可以用 SSH 推送代码了。**

---

## 5. 修改 Git 远程 URL 为 SSH

### 5.1 查看当前远程地址

    git remote -v

若仍是 HTTPS：

    origin  https://github.com/RSKyo/study.git (fetch)
    origin  https://github.com/RSKyo/study.git (push)

则需要改成 SSH。

### 5.2 将 `origin` 改为 SSH URL

    git remote set-url origin git@github.com:RSKyo/study.git

再检查：

    git remote -v

理想输出：

    origin  git@github.com:RSKyo/study.git (fetch)
    origin  git@github.com:RSKyo/study.git (push)

只要这里是 `git@github.com:...` 这种形式，之后的 `git push origin main` 就都会走 SSH。

---

## 6. 用 SSH 重新推送

在项目目录执行：

    git push origin main

典型输出（成功时）：

    Enumerating objects: ...
    Counting objects: ...
    Compressing objects: ...
    Writing objects: ...
    To github.com:RSKyo/study.git
       <旧哈希>..<新哈希>  main -> main

关键点：  
`To github.com:RSKyo/study.git` 说明走的是 SSH，push 已成功。

---

## 7. 最终确认：本地与远程是否同步

### 7.1 再次查看状态

    git status

理想结果：

    On branch main
    Your branch is up to date with 'origin/main'.
    nothing to commit, working tree clean

说明本地 `main` 与远程 `origin/main` 完全一致。

---

### 7.2 可选：用 log 检查差异

    git log origin/main..main --oneline

- 若没有任何输出：本地和远程没有差异。  
- 若有输出：这些就是“本地有但远程没有”的提交（说明 push 仍未成功）。

---

## 8. 问题总表：错误 → 原因 → 方案

| 问题现象 | 可能原因 | 解决方案 |
|----------|----------|----------|
| `ahead by 1 commit` | 本地提交成功但 push 失败 | 解决 push 问题并再次推送 |
| `error: RPC failed; HTTP 400` | HTTPS 网络/代理导致请求被拒或中断 | 改用 SSH 推送 |
| `fatal: the remote end hung up unexpectedly` | 远程或中间层主动断开连接 | 同上，改走 SSH |
| `REMOTE HOST IDENTIFICATION HAS CHANGED!` | 本地缓存的 GitHub host key 过期/不一致 | 使用 `ssh-keygen -R github.com` 删除旧记录，再重新连接 |

---

## 9. 常用命令速查表（本次排查用到的）

|命令|功能|
|---|---|
|`git status`|查看同步状态|
|`git remote -v`|查看远程地址|
|`git ls-remote origin`|检查远程可访问|
|`ssh-keygen -t ed25519 -C "邮箱"`|生成 SSH 密钥|
|`cat ~/.ssh/id_ed25519.pub`|查看公钥内容|
|`ssh -T git@github.com`|测试 SSH 连接|
|`ssh-keygen -R github.com`|删除旧 host 记录|
|`git remote set-url origin git@github.com:<user>/<repo>.git`|改为 SSH|
|`git push origin main`|推送代码|
|`git log origin/main..main --oneline`|检查差异|

---

## 10. 一句话经验

- **commit 只是保存到本地历史，push 才是同步到 GitHub**。  
- 如果频繁遇到 HTTPS 推送失败（400 / 断连），**直接改用 SSH 是最省心的长期方案**。  
- 看到 “ahead by X commits” 不必慌，只要让某一次 push 真正成功，这个提示就会消失，本地与远程重新对齐。
