FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list     && apt-get update && apt-get install -y --no-install-recommends     sudo findutils gcc openssh-server     && rm -rf /var/lib/apt/lists/*     && useradd -m -s /bin/bash lowpriv     && echo 'lowpriv:lowpriv123' | chpasswd     && echo 'root:toor' | chpasswd     && mkdir -p /var/run/sshd
# 漏洞配置: sudoers 保留 LD_PRELOAD 环境变量 (env_keep)
RUN echo 'lowpriv ALL=(root) NOPASSWD: /usr/bin/find' > /etc/sudoers.d/lowpriv     && echo 'Defaults env_keep += "LD_PRELOAD"' >> /etc/sudoers.d/lowpriv     && chmod 440 /etc/sudoers.d/lowpriv
CMD ["/usr/sbin/sshd", "-D"]
