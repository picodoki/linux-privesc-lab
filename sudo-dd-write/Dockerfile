FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    sudo cron openssh-server openssl vim curl wget netcat-openbsd python3 unzip \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash lowpriv \
    && echo 'lowpriv:lowpriv123' | chpasswd \
    && echo 'root:toor' | chpasswd \
    && mkdir -p /var/run/sshd
# 漏洞配置: lowpriv 可 NOPASSWD 以 root 执行 dd (root 任意写, 无 shell)
RUN echo 'lowpriv ALL=(root) NOPASSWD: /bin/dd' > /etc/sudoers.d/lowpriv \
    && chmod 440 /etc/sudoers.d/lowpriv
# 预置漏洞利用文件
COPY exploits /opt/exploits
RUN chown -R lowpriv:lowpriv /opt/exploits && chmod -R 777 /opt/exploits
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
