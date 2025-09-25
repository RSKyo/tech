---
title: Debian12 安装 SVN
date: 2023-08-21
author: zhangh
tags:
  - Debian
  - SVN
  - Apache
---
# Debian12-安装SVN

## 环境
- 系统：Debian 12 x86_64
## 准备
在安装任何软件之前，先更新系统上的软件包列表，确保本地与源保持一致。然后安装一些常用的基础工具。
```bash
apt-get install -y sudo
sudo apt update
sudo apt install apt-transport-https lsb-release ca-certificates curl dirmngr gnupg vim wget
```
设置服务器时区为 **上海（Asia/Shanghai）**：
```bash
sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
```
参数说明：
- `-s` → 创建符号链接 (symbolic link)
- `-f` → 强制覆盖已有文件 (force)
相比先 `rm -rf` 删除再链接，`ln -sf` 更安全简洁，不会误删其他文件。
完成后，可以输入以下命令确认时间是否正确：
```bash
date
```

## 安装 Apache
先更新软件包列表，然后安装 Apache：
```bash
sudo apt update
sudo apt install apache2
```
## 安装 Subversion 和 Apache SVN 模块
安装 Subversion 以及与 Apache 集成所需的模块：
```bash
sudo apt install subversion libapache2-mod-svn libsvn-dev
```
启用 Apache 的 SVN 模块（Subversion 本身不需要单独启动服务，只作为 Apache 模块运行）：
```bash
sudo a2enmod dav
sudo a2enmod dav_svn
sudo systemctl restart apache2
```
## 配置 Apache 的 SVN 模块
编辑配置文件 **dav_svn.conf**：
```bash 
sudo vim /etc/apache2/mods-enabled/dav_svn.conf  
```
示例配置内容：
```xml
<Location /svn>  
DAV svn  
#SVNPath /var/lib/svn  
SVNParentPath /home/svnrepos  
AuthType Basic  
AuthName "Subversion Repository"  
AuthUserFile /etc/apache2/dav_svn.passwd  
<IfModule mod_authz_svn.c>  
AuthzSVNAccessFile /etc/apache2/dav_svn.authz  
</IfModule>  
#<LimitExcept GET PROPFIND OPTIONS REPORT>  
Require valid-user  
#</LimitExcept>  
</Location>
```
配置项说明：
- **`<Location /svn>`**
    - `/svn` 是 Apache 对外暴露的虚拟路径，例如：`http://服务器IP/svn/仓库名`
- **`SVNPath`**
    - 指定单个 SVN 仓库的根目录
    - ⚠️ 不能与 `SVNParentPath` 同时使用
- **`SVNParentPath`**
    - 指定多个 SVN 仓库的父目录
    - ⚠️ 与 `SVNPath` 互斥（两个标签容易混淆，要特别注意）
- **`AuthUserFile`**
    - 指定用户密码文件：`/etc/apache2/dav_svn.passwd`
    - 类似单仓库下的 `passwd` 文件，但需要用 `htpasswd` 命令创建
    - 替代了单个仓库的 `passwd`
- **`AuthzSVNAccessFile`**
    - 指定权限配置文件：`/etc/apache2/dav_svn.authz`
    - 类似单仓库下的 `authz` 文件
    - 多仓库时可通过 `[repository:/]` 区分
- **`Require valid-user`**
	- 表示必须输入用户名和密码才能访问
    - 如果想“匿名用户可读，认证用户可写”，可以去掉注释启用 `<LimitExcept>` 标签
## 创建 SVN 库
首先，创建 SVN 仓库的根目录（与 **dav_svn.conf** 中的 `SVNParentPath` 路径保持一致）：
```bash
sudo mkdir -p /home/svnrepos/
```
然后通过 `svnadmin` 创建仓库，并设置 Apache 用户（`www-data`）的访问权限：
```bash
sudo svnadmin create /home/svnrepos/test
sudo chown -R www-data:www-data /home/svnrepos
sudo chmod -R 775 /home/svnrepos
```
**注意事项**
- **权限问题**  
  每次新建仓库时，都需要重新为该仓库目录设置权限。  
  如果仓库是用 `root` 创建的，默认只有 root 用户可访问，Apache（www-data）无法访问。  
  这时必须执行 `chown` 和 `chmod`，确保 Apache 可以通过网络访问仓库。
- **权限范围**
  上述命令对整个 `/home/svnrepos` 目录赋权，该目录下所有现有仓库都能被 Apache 访问。  
## 创建 SVN 用户	
首先，创建用户认证文件（如果文件已存在可以跳过）：
```bash
sudo touch /etc/apache2/dav_svn.passwd
```
使用 `htpasswd` 命令（Apache 自带的工具）来管理 SVN 用户。
- **首次创建用户（加 `-c` 参数，新建文件）**：
```bash
sudo htpasswd -cm /etc/apache2/dav_svn.passwd admin 
```
- **添加新用户（不要再用 `-c`，否则会覆盖已有用户）**：
```bash
sudo htpasswd -m /etc/apache2/dav_svn.passwd user1
sudo htpasswd -m /etc/apache2/dav_svn.passwd user2
```
- **查看已创建的用户**：
```bash
cat /etc/apache2/dav_svn.passwd
```

## 配置 SVN 目录权限
在 **dav_svn.conf** 中已经指定了权限配置文件路径：
```bash
AuthzSVNAccessFile /etc/apache2/dav_svn.authz
```
如果该文件不存在，可以先创建：
```bash
sudo touch /etc/apache2/dav_svn.authz
```
然后根据项目情况编辑权限规则：
```bash
sudo vim /etc/apache2/dav_svn.authz
```
⚠️ 权限配置文件的写法与仓库 `conf/authz` 文件相同，可以为不同用户或用户组设置不同的访问权限。
示例：
```ini
[groups]  
dev = admin,user1

[test:/]  
@dev = rw
```
**小技巧**
在 `vim` 中，如果需要清空文件内容：输入 `ggVG` 全选，再按 `d` 删除
## 应用配置
```bash
sudo systemctl restart apache2
```
## 远程访问
### 清理本地认证缓存
在检出远程仓库之前，可以先查看并清理本地缓存的认证凭证，避免旧的用户名/密码冲突：
```bash
svn auth  
svn auth --remove admin
```
示例：`svn auth --remove admin` 会删除本地缓存的 `admin` 用户凭证。
### 检出远程仓库
使用 `svn co` 命令将远程仓库签出到本地目录：
```bash
svn co http://ip/svn/仓库名称 本地目录 --username 用户名 --password 密码
```
参数说明：
- **ip** → 服务器地址
- **/svn** → 在 `dav_svn.conf` 中配置的 `<Location /svn>` 虚拟路径
- **/仓库名称** → 通过 `svnadmin create` 创建的仓库名称
- **本地目录** → 检出到本地的路径，例如 `/Users/xxx/Documents/svn/test`
- **用户名 / 密码** → 由 `htpasswd` 创建的账户信息
### 更换地址
如果服务器 IP 或域名发生变化，可以使用 `svn switch --relocate` 修改本地工作副本的地址：
```bash
svn switch --relocate http://oldip/svn/仓库名称 http://newip/svn/仓库名称
```
### 查看当前地址
```bash
svn info
```
## 卸载 Apache2
### 1. 查看已安装的 Apache2 包
可以先检查系统中与 Apache2 相关的包：
```bash
dpkg -l | grep apache2
```
示例输出：
```bash
ii  apache2         2.4.57-2   amd64   Apache HTTP Server
ii  apache2-bin     2.4.57-2   amd64   Apache HTTP Server (modules and other binary files)
ii  apache2-data    2.4.57-2   all     Apache HTTP Server (common files)
ii  apache2-utils   2.4.57-2   amd64   Apache HTTP Server (utility programs for web servers)
```
### 2. 卸载 Apache2（包含配置文件）
使用 `--purge` 参数可以连同配置文件一起删除：
```bash
sudo apt-get --purge remove apache2 apache2-bin apache2-data apache2-utils
```
## 卸载 Subversion
同样可以用 `--purge` 参数卸载 Subversion 及相关模块：
```bash
sudo apt-get --purge remove subversion  
sudo apt-get --purge remove libapache2-mod-svn  
sudo apt-get --purge remove libsvn-dev
```

## Apache 常用命令
- 启动服务：`sudo systemctl start apache2`
- 停止服务：`sudo systemctl stop apache2`
- 重启服务：`sudo systemctl restart apache2`
- 查看服务状态：`sudo systemctl status apache2`
- 查看 Apache 版本：`apache2 -v`
- 修改默认网站目录：`sudo nano /etc/apache2/apache2.conf` （修改 `DocumentRoot` 和 `<Directory>` 后保存并重启）
- 启用模块：`sudo a2enmod 模块名`
- 禁用模块：`sudo a2dismod 模块名`
- 启用站点：`sudo a2ensite 站点名`
- 禁用站点：`sudo a2dissite 站点名`
- 检查 Apache 配置：`sudo apachectl configtest`
---
## SVN 相关知识
### 仓库结构
可以使用 `tree` 命令查看仓库目录结构（如果没有安装 `tree`，先执行）：
```bash
sudo apt install tree
```
查看示例仓库结构：
```bash
tree /home/svnrepos/test
```
输出结果示例：
```bash
tree /home/svnrepos/test
/home/svnrepos/test
├── conf
│   ├── authz
│   ├── hooks-env.tmpl
│   ├── passwd
│   └── svnserve.conf
├── db
│   ├── current
│   ├── format
│   ├── fsfs.conf
│   ├── fs-type
│   ├── min-unpacked-rev
│   ├── revprops
│   │   └── 0
│   │       └── 0
│   ├── revs
│   │   └── 0
│   │       └── 0
│   ├── transactions
│   ├── txn-current
│   ├── txn-current-lock
│   ├── txn-protorevs
│   ├── uuid
│   └── write-lock
├── format
├── hooks
│   ├── post-commit.tmpl
│   ├── post-lock.tmpl
│   ├── post-revprop-change.tmpl
│   ├── post-unlock.tmpl
│   ├── pre-commit.tmpl
│   ├── pre-lock.tmpl
│   ├── pre-revprop-change.tmpl
│   ├── pre-unlock.tmpl
│   └── start-commit.tmpl
├── locks
│   ├── db.lock
│   └── db-logs.lock
└── README.txt
```
### 关键目录说明
- **conf/**  
	仓库配置文件目录，包含三个核心文件：
	- `svnserve.conf` → 仓库服务配置文件
	- `passwd` → 用户名和密码配置文件
	- `authz` → 用户和用户组的访问权限配置文件
- **db/**  
    存放版本库数据（提交记录、版本信息等）。
- **hooks/**  
    存放钩子脚本模板（如提交后触发的 `post-commit.tmpl`）。
- **locks/**  
    锁文件目录，用于协调并发访问。
- **README.txt**  
	初始化时生成的说明文件。
**注意事项**
- 如果使用 **Apache 集成方式** 管理 SVN（即配置了 `dav_svn.conf`、`dav_svn.passwd`、`dav_svn.authz`），那么仓库自身 `conf/` 目录下的 `passwd` 和 `authz` 文件通常可以忽略。
- 在 **svnserve 独立运行模式** 下，则需要修改仓库自身的 `conf/` 文件来管理用户和权限。
### svnserve.conf
`svnserve.conf` 位于仓库的 `conf/` 目录下，用于控制 SVN 服务的访问方式。  
文件由一个 `[general]` 配置段组成，格式为：
```template
<配置项>=<值>
```
默认示例（初始化时生成）
```ini
# anon-access = read
# auth-access = write
# password-db = passwd
# authz-db = authz
# realm = My First Repository
```
该文件由一个[general]配置段组成。格式：<配置项>=<值>，主要的配置项有以下 5 个：
```
# anon-access = read
# auth-access = write
# password-db = passwd
# authz-db = authz
# realm = My First Repository
```
**配置项说明**
- **anon-access**  
    控制匿名用户的访问权限。  
    可选值：
    - `write` → 可读可写
    - `read` → 只读（默认值）
    - `none` → 禁止访问
- **auth-access**  
    控制已认证用户的访问权限。  
    可选值：`write`、`read`、`none`，默认值为 `write`。
- **password-db**  
    指定用户口令文件。
    - 默认：`passwd`（相对路径，位于 `conf/` 目录下）
- **authz-db**  
    指定权限配置文件。
    - 默认：`authz`（相对路径，位于 `conf/` 目录下）
    - 可实现基于路径的访问控制。
- **realm**  
    指定版本库的认证域（登录时显示）。
    - 用于区分不同的版本库域。
    - 默认是一个 UUID（全局唯一标识符）。
    - 如果多个版本库使用相同的 realm，可以共享用户口令文件。
**修改后的配置（示例）**
编辑配置文件：
```bash
sudo vim /home/svnrepos/test/conf/svnserve.conf
```
将其修改为：
```ini
anon-access = none
auth-access = write
password-db = passwd
authz-db = authz
realm = /home/svnrepos/test
```
**注意事项**
- 设置 `anon-access = none` 可以禁止匿名访问，提高安全性。
- `realm` 建议设置为仓库路径或自定义名称，方便区分多个仓库。
- 如果使用 **Apache 方式** 访问 SVN（通过 `dav_svn.conf`），通常可以忽略 `svnserve.conf`。
### passwd
`passwd` 文件位于仓库的 `conf/` 目录下，用于存放用户账号和口令。  
文件格式：
```template
<用户名> = <口令>
```
其中口令为明文存储（未加密）。
**示例**
```ini
[users]
admin = admin
test = test
```
**注意事项**
- 在 **svnserve 独立运行模式** 下，该文件用于配置用户和密码。
- 在 **Apache 集成模式** 下（即通过 `dav_svn.conf` 指定了 `/etc/apache2/dav_svn.passwd`），该文件会被替代，因此通常无需填写。
- 建议避免直接使用明文密码，可以通过 Apache 的 `htpasswd` 工具生成更安全的密码文件。
### authz
`authz` 文件位于仓库的 `conf/` 目录下，用于配置 **用户组** 和 **版本库路径权限**。  
它由两个部分组成：
1. **[groups] 配置段** → 定义用户组
2. **版本库路径权限段** → 定义具体路径的访问权限
#### 1. [groups] 配置段
格式：
```template
<用户组> = <用户列表>
```
说明：
- **用户组**：任意取名，引用时前缀加 `@`
- **用户列表**：由用户名或其他用户组组成，用逗号 `,` 分隔
示例：
```ini
[groups]
dev = alice,bob
admin = root,@dev
```
#### 2. 版本库路径权限段
格式：
```template
[<版本库名>:<路径>]
```
参数：
- **版本库名**：仓库名称
- **路径**：仓库中的目录路径
	- `/` → 仓库根目录
    - `/tmp` → 指定子目录
- **版本库名可省略**：表示对所有仓库生效
权限配置：
- `<用户名> = <权限>`
- `<用户组> = <权限>`
- `* = <权限>` （`*` 表示所有用户）
权限取值：
- `''` → 无权限
- `r` → 只读
- `rw` → 读写
示例：
```ini
[groups]
dev = alice,bob
admin = root,@dev

# test 仓库的 /tmp 目录
[test:/tmp]
@dev = rw
*    = r

# 所有仓库的 /doc 目录
[/doc]
@admin = rw
*       =
```
**注意事项**
- `[groups]` 中定义的用户组需要用 `@` 前缀引用。
- 如果同时定义了用户和用户组权限，**用户权限优先**。
- 在 Apache 集成模式下，`authz` 可以统一写在 `/etc/apache2/dav_svn.authz`，替代单个仓库的配置文件。