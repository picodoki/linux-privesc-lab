FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list     && apt-get update && apt-get install -y --no-install-recommends     sudo openssh-server     && rm -rf /var/lib/apt/lists/*     && useradd -m -s /bin/bash lowpriv     && echo 'lowpriv:lowpriv123' | chpasswd     && echo 'root:toor' | chpasswd     && mkdir -p /var/run/sshd
# 漏洞配置: lowpriv 可 NOPASSWD 执行 env (配合环境函数注入)
RUN echo 'lowpriv ALL=(root) NOPASSWD: /usr/bin/env' > /etc/sudoers.d/lowpriv     && chmod 440 /etc/sudoers.d/lowpriv
CMD ["/usr/sbin/sshd", "-D"]
