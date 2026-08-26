FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list     && apt-get update && apt-get install -y --no-install-recommends     john openssh-server     && rm -rf /var/lib/apt/lists/*     && useradd -m -s /bin/bash lowpriv     && echo 'lowpriv:lowpriv123' | chpasswd     && echo 'root:password123' | chpasswd     && mkdir -p /var/run/sshd
# 漏洞配置: /etc/shadow 对所有人可读 (默认 640, 改为 644)
RUN chmod 644 /etc/shadow
CMD ["/usr/sbin/sshd", "-D"]
