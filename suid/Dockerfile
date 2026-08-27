FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list     && apt-get update && apt-get install -y --no-install-recommends     vim vim-tiny less findutils python3 openssh-server curl wget netcat-openbsd python3 unzip     && rm -rf /var/lib/apt/lists/*     && useradd -m -s /bin/bash lowpriv     && echo 'lowpriv:lowpriv123' | chpasswd     && echo 'root:toor' | chpasswd     && mkdir -p /var/run/sshd
# 漏洞配置: 故意给危险程序设置 SUID 位
RUN chmod u+s /usr/bin/find /usr/bin/vim.basic /usr/bin/less /usr/bin/base64     && cp /usr/bin/python3 /usr/local/bin/python3suid     && chmod u+s /usr/local/bin/python3suid
# 预置漏洞利用文件 (容器内 /opt/exploits, lowpriv 可读可写可执行)
COPY exploits /opt/exploits
RUN chown -R lowpriv:lowpriv /opt/exploits && chmod -R 777 /opt/exploits

CMD ["/usr/sbin/sshd", "-D"]
