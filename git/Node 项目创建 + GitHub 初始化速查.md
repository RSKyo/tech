## 1. 创建项目

```bash
mkdir project-name

cd project-name
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

推荐配置：

```json
{
"name": "项目名", 
"version": "0.1.0",
"description": "项目描述",
"type": "module", // 现代 Node 项目推荐 module

// 注册命令行工具，比如"my-tool": "./cmd.js"
"bin": {
"命令名": "命令脚本" 
},

// 定义快捷命令
// 在项目跟目录执行 npm start，等价于 node ./cmd.js
"scripts": {
"start": "node ./cmd.js",
"test": "node --test" // 执行测试，Node 会自动运行*.test.js、*.spec.js
},
"keywords": [],
"author": "",
"license": "UNLICENSED"
}
/*
|许可证|说明|  
|--------|--------|  
|MIT|最宽松|  
|Apache-2.0|企业常用|  
|GPL-3.0|要求开源|  
|ISC|类似 MIT|  
|UNLICENSED|私有项目|
*/
```

如果是 CLI 工具：

```json
{
  "bin": {
    "project-name": "./cmd.js"
  }
}
```

---

## 3. 创建基础结构

简单项目推荐：

```txt
project-name/
├── cmd.js
├── README.md
├── LICENSE
├── .gitignore
└── package.json
```

创建文件：

```bash
touch README.md LICENSE .gitignore
```

---

## 4. 配置 .gitignore

```gitignore
node_modules/
.DS_Store
.env
```

---

## 5. 初始化 Git

```bash
git init
```

设置默认分支：

```bash
git config --global init.defaultBranch main
```

切换到 main：

```bash
git branch -M main
```

---

## 6. 首次提交

```bash
git add .

git commit -m "init project"
```

---

## 7. 创建 GitHub 仓库

创建同名仓库：

```txt
project-name
```

创建时不要勾选：

- Add README
- Add .gitignore
- Add License

因为本地已经存在。

---

## 8. 关联远程仓库

```bash
git remote add origin git@github.com:<username>/<project-name>.git
```

查看：

```bash
git remote -v
```

---

## 9. 首次推送

```bash
git push -u origin main
```

---

## 10. 验证状态

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

# 日常开发流程

新增或修改文件：

```bash
git add .

git commit -m "描述本次修改"

git push
```

例如：

```bash
git add .

git commit -m "add user login"

git push
```

---

# Git 常用命令

查看状态：

```bash
git status
```

查看远程仓库：

```bash
git remote -v
```

查看提交记录：

```bash
git log --oneline
```

查看当前分支：

```bash
git branch
```

查看所有分支：

```bash
git branch -a
```

---

# git push -u origin main 与 git push 的区别

首次推送推荐：

```bash
git push -u origin main
```

作用：

1. 推送代码
2. 建立追踪关系

建立后：

```txt
main
 ↓
origin/main
```

以后直接：

```bash
git push
git pull
```

即可。

如果首次使用：

```bash
git push origin main
```

虽然能推送成功，但 Git 不会记住追踪关系。

---

# Git 提交流程

```txt
修改文件
    ↓
git add .
    ↓
git commit -m "message"
    ↓
git push
```

---

# 项目结构原则

推荐：

```txt
project-name/
├── user/
├── order/
├── payment/
├── infra/
└── config/
```

不推荐一开始就：

```txt
src/
modules/
features/
```

原则：

1. 目录名表达业务含义。
2. 少一层目录就少一层复杂度。
3. 没有收益不增加抽象层。
4. 先实现，再重构。
5. 可读性优先于架构设计。

> 能平铺就平铺，业务复杂后再抽象。