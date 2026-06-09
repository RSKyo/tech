# welm Node 项目创建与 GitHub 初始化流程

## 1. 创建项目目录

```bash
cd ~/GitHub

mkdir welm-media

cd welm-media
```

---

## 2. 初始化 Node 项目

```bash
npm init -y
```

生成：

```txt
package.json
```

---

## 3. 修改 package.json

推荐：

```json
{
  "name": "welm-media",
  "version": "0.1.0",
  "type": "module",
  "private": true,

  "bin": {
    "welm-media": "./cmd.js"
  }
}
```

说明：

|字段|说明|
|---|---|
|name|项目名|
|version|当前版本|
|type=module|使用 import/export|
|private=true|防止误发布 npm|
|bin|注册 CLI 命令|

---

## 4. 创建基础目录

当前采用：

```txt
welm-media/
├── infra/
├── subtitle/
├── cmd.js
├── package.json
├── README.md
├── LICENSE
└── .gitignore
```

特点：

- 不使用 src
    
- 不使用 modules
    
- 不使用 features
    
- 业务目录直接平铺
    
- 目录名表达业务含义
    

例如未来：

```txt
welm-media/
├── infra/
├── subtitle/
├── video/
├── audio/
├── metadata/
├── ffmpeg/
├── yt/
```

---

## 5. 创建 .gitignore

```bash
touch .gitignore
```

内容：

```gitignore
node_modules/
.DS_Store
.env
```

---

## 6. 创建 README

```bash
touch README.md
```

---

## 7. 创建 LICENSE

根据需要选择：

- MIT
    
- ISC
    
- UNLICENSED
    

个人项目可后续再决定。

---

## 8. 初始化 Git

```bash
git init
```

查看状态：

```bash
git status
```

---

## 9. 首次提交

```bash
git add .

git commit -m "init welm-media"
```

---

## 10. GitHub 创建仓库

在 GitHub 创建：

```txt
welm-media
```

创建时：

不要勾选：

- Add README
    
- Add .gitignore
    
- Add License
    

因为本地已经存在。

---

## 11. 关联远程仓库

例如：

```bash
git remote add origin git@github.com:RSKyo/welm-media.git
```

查看：

```bash
git remote -v
```

输出类似：

```txt
origin  git@github.com:RSKyo/welm-media.git (fetch)
origin  git@github.com:RSKyo/welm-media.git (push)
```

---

## 12. 使用 main 分支

```bash
git branch -M main
```

推荐设置默认：

```bash
git config --global init.defaultBranch main
```

---

## 13. 首次推送

```bash
git push -u origin main
```

成功示例：

```txt
To github.com:RSKyo/welm-media.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

---

## 14. 验证状态

```bash
git status
```

正常输出：

```txt
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean
```

---

## 15. 日常开发流程

修改代码后：

```bash
git add .

git commit -m "add subtitle align"

git push
```

---

# 当前 welm 项目结构原则

## 目录表达业务

推荐：

```txt
subtitle/
video/
audio/
metadata/
```

不推荐：

```txt
src/
modules/
features/
```

除非项目规模已经大到必须增加层级。

---

## 简单优先

原则：

1. 目录名表达真实业务含义。
    
2. 没有明确收益，不增加目录层级。
    
3. 没有明确收益，不增加抽象层。
    
4. 优先可读性，而不是追求架构。
    
5. 当结构开始痛苦时，再重构。
    

---

## cmd.js 的职责

根目录：

```txt
cmd.js
```

负责：

- 解析命令
    
- 解析参数
    
- 命令路由
    
- 输出协议
    

例如：

```bash
welm-media subtitle align
```

执行链：

```txt
cmd.js
    ↓
subtitle/cmd.js
    ↓
subtitle/align.js
```

未来每个业务目录维护自己的：

```txt
subtitle/
└── cmd.js

video/
└── cmd.js
```

根目录 cmd.js 负责统一组织 group。

git push -u origin main 加-u与不加区别

区别就在于：

```
git push -u origin main
```

会建立一个**追踪关系（tracking relationship）**。

---

## 不加 -u

例如：

```
git push origin main
```

只是这一次：

```
本地 main    ↓origin/main
```

推送成功。

但 Git 不记住。