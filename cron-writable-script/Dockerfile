FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list     && apt-get update && apt-get install -y --no-install-recommends     cron vim openssh-server curl wget netcat-openbsd python3 unzip     && rm -rf /var/lib/apt/lists/*     && useradd -m -s /bin/bash lowpriv     && echo 'lowpriv:lowpriv123' | chpasswd     && echo 'root:toor' | chpasswd     && mkdir -p /var/run/sshd
# 漏洞配置: root 的 cron 每分钟执行一个 lowpriv 可写的脚本 backup.sh
# 注意: 必须 777 (666 无 x 执行位, cron 的 execve 会失败)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# 预置漏洞利用文件 (容器内 /opt/exploits, lowpriv 可读可写可执行)
COPY exploits /opt/exploits
RUN chown -R lowpriv:lowpriv /opt/exploits && chmod -R 777 /opt/exploits

CMD ["/entrypoint.sh"]
