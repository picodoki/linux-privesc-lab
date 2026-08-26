FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list     && apt-get update && apt-get install -y --no-install-recommends     vim vim-tiny less findutils base64 python3 openssh-server     && rm -rf /var/lib/apt/lists/*     && useradd -m -s /bin/bash lowpriv     && echo 'lowpriv:lowpriv123' | chpasswd     && echo 'root:toor' | chpasswd     && mkdir -p /var/run/sshd
# 漏洞配置: 故意给危险程序设置 SUID 位
RUN chmod u+s /usr/bin/find /usr/bin/vim.basic /usr/bin/less /usr/bin/base64     && cp /usr/bin/python3 /usr/local/bin/python3suid     && chmod u+s /usr/local/bin/python3suid
CMD ["/usr/sbin/sshd", "-D"]
