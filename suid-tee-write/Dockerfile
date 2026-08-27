FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    coreutils cron openssh-server openssl vim curl wget netcat-openbsd python3 unzip \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash lowpriv \
    && echo 'lowpriv:lowpriv123' | chpasswd \
    && echo 'root:toor' | chpasswd \
    && mkdir -p /var/run/sshd
# 漏洞配置: /usr/bin/tee 带 SUID (euid=0, 任意文件写, 无 shell)
RUN chmod u+s /usr/bin/tee
# 预置漏洞利用文件
COPY exploits /opt/exploits
RUN chown -R lowpriv:lowpriv /opt/exploits && chmod -R 777 /opt/exploits
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
