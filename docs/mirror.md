# Docker 国内镜像源配置

背景：2024-06-06 起国内主流 Docker 镜像加速器几乎全部停止服务（阿里云、网易、腾讯云、
高校镜像站）。阿里云个人加速器仅阿里云 ECS 内网可用（非阿里云环境返回 403）。

## 当前可用镜像源（2025-2026，社区维护）

| 镜像源 | 地址 | 说明 |
|:---|:---|:---|
| DaoCloud | https://docker.m.daocloud.io | 白名单+限流，建议凌晨拉取 |
| 轩辕镜像 | https://docker.xuanyuan.me | 社区维护 |
| 1ms.run | https://docker.1ms.run | 社区维护 |
| 1Panel | https://docker.1panel.live | 社区维护 |

## 方式一：daemon.json（宿主机级）

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.xuanyuan.me",
    "https://docker.1ms.run"
  ]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
docker info | grep -A 8 'Registry Mirrors'
```

## 方式二：Dockerfile / compose 直接换源（本项目默认方式）

给镜像名加 DaoCloud 代理前缀：

```dockerfile
FROM m.daocloud.io/docker.io/ubuntu:20.04
```

```yaml
image: m.daocloud.io/docker.io/mysql:5.7
```

## 注意

- Docker Hub 2025-04-01 起限速：未登录 10 次/小时/IP，免费账号登录 100 次/小时。
  超限返回 HTTP 429，与镜像源无关，先 docker login 免费账号。
- 本项目的 Dockerfile 均已在 apt 源层面替换为阿里云（mirrors.aliyun.com/ubuntu），
  基础镜像使用 DaoCloud 前缀，可直接构建。
