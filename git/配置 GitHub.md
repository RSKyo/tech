# GitHub 配置与推送指南

## 1. Git 基础身份配置（全局）

```bash
git config --global user.name "你的名字"
git config --global user.email "你的邮箱@example.com"
````

### GitHub 邮箱建议

你可以选择：

- 注册 GitHub 时使用的邮箱
- GitHub noreply 隐私邮箱（推荐）
- 任意邮箱（不推荐）

GitHub noreply 示例：
```
12345678+username@users.noreply.github.com
```
优点：
- GitHub 可正确关联 commit 到账号
- 隐藏真实邮箱

---

## 2. GitHub 推送方式

GitHub 支持两种认证方式：

### 2.1 HTTPS（PAT Token）

推送时会提示：
```bash
Username: your_github_username
Password: YOUR_PERSONAL_ACCESS_TOKEN
```
⚠️ 注意：不是 GitHub 密码

#### 创建 Token 路径
```
GitHub → Settings → Developer settings → Personal access tokens
```

建议：
- Fine-grained tokens（推荐）
- Classic tokens（简单）

至少权限：
- repo（必须）
- workflow（可选）

### 2.2 SSH（推荐）

#### 1）检查 SSH Key
```bash
ls -al ~/.ssh
```

如果存在：
```
id_ed25519
id_ed25519.pub
```
说明已配置

#### 2）生成 SSH Key

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

#### 3）添加到 GitHub

复制公钥：
```bash
cat ~/.ssh/id_ed25519.pub
```

GitHub：
```
Settings → SSH and GPG keys → New SSH key
```

#### 4）测试连接

```bash
ssh -T git@github.com
```

成功提示：
```
Hi username! You've successfully authenticated...
```

#### 5）切换 remote 为 SSH

```bash
git remote set-url origin git@github.com:username/repo.git
```

---

## 3. 本地项目推送流程

### 3.1 初始化 Git

```bash
cd your-project
git init
```

### 3.2 添加 .gitignore（必须）

```bash
touch .gitignore
```

推荐内容：
```
node_modules
.env
dist
build
.DS_Store
npm-debug.log
```

### 3.3 提交代码

```bash
git add .
git commit -m "initial commit"
```

### 3.4 创建 GitHub 仓库

- New repository
- ❗ 不要初始化 README（避免冲突）

### 3.5 关联远程仓库

```bash
git remote add origin https://github.com/username/repo.git
```

检查：
```bash
git remote -v
```

### 3.6 推送代码

首次推送：
```bash
git branch -M main
git push -u origin main
```

---

## 4. 常见问题

### 4.1 push 被拒绝（non-fast-forward）

```bash
git pull origin main --rebase
git push
```

### 4.2 node_modules 被提交

```bash
git rm -r --cached node_modules
git commit -m "remove node_modules"
git push
```

### 4.3 登录失败

原因：
- 使用 GitHub 密码（已废弃）

解决：
- 使用 PAT Token
- 或 SSH（推荐）
