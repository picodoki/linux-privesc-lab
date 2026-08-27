# linux-privesc-lab

![banner](docs/images/banner.png)

Linux 权限提升（Privilege Escalation）漏洞靶场实验室。每个漏洞环境独立成目录，
包含对应的 Docker 配置、漏洞利用脚本与原理讲解文档，开箱即用，类似 vulhub 靶场。

由于 docker 与宿主机共享内核，暂不提供内核提权的相关靶场。

本项目所有环境均已在真实环境逐场景验证（Kali 2026.2 / Docker 29.7.2），
验证记录见各目录 README 的"验证结果"章节。

## 环境列表

| 目录 | 漏洞/场景 | 验证状态 |
|:---|:---|:---|
| sudo-nopasswd | sudo NOPASSWD 危险命令提权 (find/python3/vim) | 已复现 |
| sudo-cve-2019-14287 | CVE-2019-14287 sudo 用户 ID 绕过 | 需 sudo < 1.8.28 |
| sudo-cve-2023-22809 | CVE-2023-22809 sudoedit EDITOR 注入 | 需 sudo < 1.9.12p2 |
| suid | SUID 提权 (find/vim/less/base64/python3) | 已复现 |
| capabilities | Linux capabilities (cap_setuid) 提权 | 已复现 |
| cron-writable-script | cron 可写脚本提权 | 已复现 |
| cron-tar-wildcard | cron tar 通配符参数注入 | 已复现 |
| cron-path-hijack | cron PATH 劫持 | 已复现 |
| passwd-writable | /etc/passwd 可写提权 | 已复现 |
| shadow-readable | /etc/shadow 可读 + john 破解 | 已复现 |
| ld-preload | LD_PRELOAD 环境变量劫持 | 已复现 |
| bash-func-hijack | BASH_FUNC_ 环境函数劫持 | 已复现 |
| mysql-udf | MySQL UDF 提权 (sys_exec/sys_eval) | 已复现 |
| sudo-tee-write | 组合拳: sudo tee 任意文件写 -> 写 cron/passwd/反弹 shell | 已复现 |
| sudo-cp-write | 组合拳: sudo cp 覆盖 cron 脚本/系统文件 | 已复现 |
| sudo-dd-write | 组合拳: sudo dd 写 cron/追加 passwd | 已复现 |
| suid-tee-write | 组合拳: SUID tee 追加 passwd/写 cron | 已复现 |

## 快速开始

每个环境目录独立构建启动，统一账号：

- 低权限用户：lowpriv / lowpriv123
- root：toor
- MySQL root（mysql-udf 环境）：root

```bash
# 进入某个漏洞环境
cd sudo-nopasswd

# 构建并启动
docker compose up -d --build

# 进入低权限用户 shell
docker exec -it $(docker compose ps -q) su - lowpriv

# 查看该环境的利用说明
cat README.md

# 一键利用（以低权限用户运行）
bash /opt/exploits/exploit.sh
```

国内网络加速：所有镜像均使用 DaoCloud 国内代理前缀拉取（m.daocloud.io/docker.io/...），
apt 源已替换为阿里云。若需配置 Docker daemon 级镜像加速，见 docs/mirror.md。

## 目录结构

```
linux-privesc-lab/
├── README.md                    # 本文件
├── docs/
│   └── mirror.md                # Docker 国内镜像源配置指南
├── sudo-nopasswd/               # 每个环境包含:
│   ├── Dockerfile               #   docker 镜像配置
│   ├── docker-compose.yml       #   一键编排
│   ├── exploit.sh               #   漏洞利用脚本（一键执行）
│   └── (源码/编译脚本)        #   容器内预置于 /opt/exploits
│   └── README.md                #   原理讲解 + 复现步骤 + 验证记录
├── sudo-cve-2019-14287/
├── sudo-cve-2023-22809/
├── suid/
├── capabilities/
├── cron-writable-script/
├── cron-tar-wildcard/
├── cron-path-hijack/
├── passwd-writable/
├── shadow-readable/
├── ld-preload/
├── bash-func-hijack/
└── mysql-udf/
└──sudo-tee-write/
└──sudo-cp-write/
└──sudo-dd-write/	
└──suid-tee-write/
```

## 免责声明

本靶场仅用于授权环境下的安全测试与教学研究，禁止用于非法用途。
