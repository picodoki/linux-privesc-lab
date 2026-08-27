#!/bin/bash
# 一键编译 MySQL UDF 库
cd "$(dirname "$0")"
gcc -shared -fPIC -I/usr/include/mysql -o udf_exec.so udf_exec.c
if [ $? -eq 0 ]; then
    echo "[+] 编译成功: $(pwd)/udf_exec.so"
else
    echo "[-] 编译失败, 请确认 libmysqlclient-dev 已安装"
fi
