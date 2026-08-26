FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
# apt 换阿里云源加速
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list     && apt-get update && apt-get install -y --no-install-recommends     sudo vim vim-tiny python3 gcc openssh-server     && rm -rf /var/lib/apt/lists/*     && useradd -m -s /bin/bash lowpriv     && echo 'lowpriv:lowpriv123' | chpasswd     && echo 'root:toor' | chpasswd     && mkdir -p /var/run/sshd
# 漏洞配置: NOPASSWD 放开危险命令
RUN echo 'lowpriv ALL=(ALL:ALL) NOPASSWD: /usr/bin/find, /usr/bin/python3, /usr/bin/vim' > /etc/sudoers.d/lowpriv     && chmod 440 /etc/sudoers.d/lowpriv     && ln -sf /usr/bin/vim.basic /usr/bin/vim
CMD ["/usr/sbin/sshd", "-D"]
