#!/bin/bash
# 启动时配置 MySQL UDF 提权环境 (全部为实机验证后的修复版配置)
cat >> /etc/mysql/mysql.conf.d/mysqld.cnf <<'EOF'
[mysqld]
bind-address = 0.0.0.0
secure-file-priv = ""
user = root
EOF
# 关键修复: mysqld 参数首个生效, 默认配置 user=mysql 会覆盖 --user=root, 必须替换掉
sed -i 's/^user\s*=\s*mysql$/user = root/' /etc/mysql/mysql.conf.d/mysqld.cnf
mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld && chmod 755 /var/run/mysqld
# 直接以 root 启动 mysqld (mysqld_safe 的 user=root 反而不传 --user, 导致降权)
/usr/sbin/mysqld --user=root --daemonize \
  --bind-address=0.0.0.0 --secure-file-priv= \
  --socket=/var/run/mysqld/mysqld.sock \
  --pid-file=/var/run/mysqld/mysqld.pid \
  --log-error=/var/log/mysql/error.log
sleep 8
# MySQL 8.0: root@localhost 默认 auth_socket 插件, 改为密码认证 + 创建远程 root
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'root'; CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY 'root'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;"
# plugin 目录可写 (UDF 上传前提)
chmod 777 /usr/lib/mysql/plugin
# 测试库
mysql -e "CREATE DATABASE IF NOT EXISTS app; USE app; CREATE TABLE IF NOT EXISTS users(id INT, username VARCHAR(32), password VARCHAR(64)); INSERT INTO users VALUES(1,'admin','admin888');"
# 服务
sed -i 's/#*PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
service ssh start
echo "[+] mysql-udf ready: mysql root/root, mysqld runs as root"
tail -f /dev/null
