


```txt
本地领先远程 N 个提交
远程领先本地 M 个提交
如何保留线性历史
```

如下图：
本地和远程都产生了新的提交
双方出现分叉(diverged)
```txt
          A---B---C---D  (main)
         /
3772154
         \
          E           (origin/main)
```

共同祖先是：
```txt
3772154
```

你本地有：
```txt
A B C D
```

远程有：
```txt
E
```

查看分叉：
```bash
git log --oneline --graph --decorate --all
```

---

## 推荐处理方式：

```bash
git pull --rebase
git push
```

原理：
```txt
1. 拉取远程最新提交
2. 本地分支移动到远程最新提交
3. 本地重新播放提交(rebase = replay commits)
4. push 到远程
```

开始时：
```txt
      A---B---C---D (main)
     /
----*
     \
      E (origin/main)
```
此时你的本地仓库其实还不知道 远程服务器上有 E。

第一步：
`pull` 的前半部分其实是：`git fetch`
把远程信息下载到本地，于是本地仓库变成：
```txt
      A---B---C---D (main)
     /
----*
     \
      E (origin/main)
```
注意：此时只是下载，main 没动。

第二步：重新播放提交(rebase = replay commits)
1、保存 A B C D
```
Patch A
Patch B
Patch C
Patch D
```

2、main 移到 E
```txt
----*---E
        ↑
       main
    origin/main
```

应用 A
Git 创建新的提交 A'
```txt
----*---E---A'
            ↑
           main
        ↑
    origin/main
```
注意：origin/main 仍然指向 E

应用 B
```txt
----*---E---A'---B'
                 ↑
                main
        ↑
    origin/main
```

应用 C
```txt
----*---E---A'---B'---C'
                      ↑
                     main
        ↑
    origin/main
```

应用 D
```txt
----*---E---A'---B'---C'---D'
                           ↑
                          main
        ↑
    origin/main
```

最后：
```bash
git push
```
远程仓库收到 A' B' C' D' 之后远程分支才会更新，同时，本地的 `origin/main` 也会同步更新到远程最新位置。
```txt
----*---E---A'---B'---C'---D'
                           ↑
                          main
                           ↑
                       origin/main
```

