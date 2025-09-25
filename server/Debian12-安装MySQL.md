# Debian12-安装MySQL
2023-08-21 zhangh create

## 系统环境
Debian 12 x86_64

## 准备
在安装任何软件之前，先使用apt update命令同步系统上的软件包列表，使系统上的PPA 和存储库获取最新的软件包列表。之后再安装一些基础工具。
```
# apt-get install -y sudo
# sudo apt update
# sudo apt install apt-transport-https lsb-release ca-certificates curl dirmngr gnupg vim wget
```
更改服务器时间为国内时间：
```
# rm -rf /etc/localtime
# ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
```
完成后，输入 `# date` 命令查看

## 安装 mysql-apt-config
在准备工作中更新的软件列表中并不包含 MySQL，你需要在系统中添加 MySQL APT 配置文件来启用 MySQL 存储库。
最新的 MySQL APT 配置文件可以在 https://dev.mysql.com/downloads/repo/apt/ 查看。
**特别是安装时出现提示不符合系统版本时，有可能需要 mysql-apt-config 的最新版。**
下载并安装 MySQL APT 配置：
```
# wget https://dev.mysql.com/get/mysql-apt-config_0.8.28-1_all.deb
# sudo apt update
# sudo dpkg -i mysql-apt-config_0.8.28-1_all.deb
```
在安装过程中，系统将提示你选择要安装的MySQL产品和版本：
```
Which MySQL product do you wish to configure? → MySQL Server & Cluster
Which server version do you wish to receive? → mysql-8.0
```
选择完成后，在选项列表选择最后一个选项 [OK] ，回车完成安装。
启用 MySQL 存储库后，使用apt update命令更新软件列表：
```
# sudo apt update
```
## 安装 MySQL
```
sudo apt install mysql-server mysql-client
```
安装时，系统会提示你为 MySQL 设置 root 密码；下一步会让你选择一种加密方式（两种都可以），等待安装完成。
**以上命令安装可能会时错：缺少依赖 libssl1.1(＞= 1.1.1)，下载并安装 libssl 即可：**
```
wget https://mirrors.tuna.tsinghua.edu.cn/debian/pool/main/o/openssl/libssl1.1_1.1.1n-0%2Bdeb11u5_amd64.deb
sudo dpkg -i libssl1.1_1.1.1n-0+deb11u5_amd64.deb
```
测试 MySQL 是否安装完成：
```
# mysql -u root -p
# Enter password: 输入密码
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 11
Server version: 8.0.34 MySQL Community Server - GPL

Copyright (c) 2000, 2023, Oracle and/or its affiliates.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> show databases;
+--------------------+
| Database           |
+--------------------+
| information_schema |
| mysql              |
| performance_schema |
| sys                |
+--------------------+
4 rows in set (0.01 sec)
```
查看 MySQL 是否正常启动，显示内容中 mysql 节点为 LISTEN 表面启动成功。
```
sudo netstat -tap | grep mysql
```
启动、关闭、重启 MySQL 命令
```
sudo service mysql start
sudo service mysql stop
sudo service mysql restart
```

## 远程登录
查看用户的访问权限：
```
mysql> use mysql;
Database changed
mysql> select User, Host from user;
+------------------+-----------+
| User             | Host      |
+------------------+-----------+
| mysql.infoschema | localhost |
| mysql.session    | localhost |
| mysql.sys        | localhost |
| root             | localhost |
+------------------+-----------+
5 rows in set (0.00 sec)
```
可以看到 root 用户的 Host 为 localhost，只能本机登录。
开启远程访问权限有两种方式：改表法 和 授权法。
该表法顾名思义，直接修改 user 表里的 Host 项，从 “localhost“ 改为 “%”
```
mysql> update user set host='%' where user='root';
```
授权法则通过 GRANT 命令授予主机远程访问的权限。
```
# MySQL8.0 之前可用
mysql> grant all privileges on to ‘root’@‘%’ identified by ‘密码’ with grant option;

# MySQL8.0 之后
mysql> create user '用户名'@'%' identified by '新密码';
mysql> grant all privileges on *.* to '用户名'@'%' with grant option;

# 更新权限
mysql> flush privileges;
```

## 修改字符集
查看当前字符集：
```
mysql> status
--------------
mysql  Ver 8.0.34 for Linux on x86_64 (MySQL Community Server - GPL)

Connection id:          28
Current database:
Current user:           root@localhost
SSL:                    Not in use
Current pager:          stdout
Using outfile:          ''
Using delimiter:        ;
Server version:         8.0.34 MySQL Community Server - GPL
Protocol version:       10
Connection:             Localhost via UNIX socket
Server characterset:    utf8mb4
Db     characterset:    utf8mb4
Client characterset:    utf8mb4
Conn.  characterset:    utf8mb4
UNIX socket:            /var/run/mysqld/mysqld.sock
Binary data as:         Hexadecimal
Uptime:                 1 hour 2 min 38 sec

Threads: 5  Questions: 151  Slow queries: 0  Opens: 303  Flush tables: 3  Open tables: 222  Queries per second avg: 0.040
--------------
```
可以看到新安装的 MySQL 默认都是 utf8mb4 ，utf8mb4 是 utf-8 的扩展，这里无需更改字符集。

## utf8mb3、utf8mb4
UTF-8是一种用于编码Unicode字符的可变长度字符编码标准。"utf8mb4"和"utf8mb3"则是UTF-8的两个变种。它们的主要区别在于能够表示的字符范围。
UTF-8使用1到4个字节来编码不同范围的Unicode字符。"utf8mb3"以前被称为普通的UTF-8，在这个编码中，使用最多3个字节来表示Unicode字符。这意味着"utf8mb3"可以表示Unicode字符的范围是从U+0000到U+FFFF。
而"utf8mb4"是对"utf8mb3"的扩展，它使用最多4个字节表示Unicode字符。由于"utf8mb4"可以处理更多的字节，因此可以表示更广泛的Unicode字符范围，包括一些辅助平面字符（Supplementary Planes），如Emoji表情符号和一些特殊符号。"utf8mb4"的字符范围从U+0000到U+10FFFF。

## 修改字符集
如果你需要修改默认字符集，可以使用 whereis 和 find 命令查找 my.cnf 文件。
```
whereis mysql
find / -name 'my.cnf'
```
my.cnf 文件在 /etc/mysql 下
```
vim /etc/mysql/my.cnf
# 内容
!includedir /etc/mysql/conf.d/
!includedir /etc/mysql/mysql.conf.d/
```
意思是配置文件在这两个目录下，这两个目录下各有一个配置文件，分别为 mysql.cnf 和 mysqld.cnf ，修改 mysqld.cnf 把 character-set-server=你指定的字符集 放在 [mysqld] 的最后。
```
vim /etc/mysql/mysql.conf.d/mysqld.cnf
# 内容
[mysqld]
pid-file =  /var/run/mysqld/mysqld.pid
socket =    /var/run/mysqld/mysqld.sock
datadir =   /var/lib/mysql
log-error = /var/log/mysql/error.log
character-set-server=你指定的字符集
```
修改后，保存退出，重启 MySQL。
```
sudo service mysql restart
```