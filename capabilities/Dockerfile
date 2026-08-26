FROM m.daocloud.io/docker.io/ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g; s@//security.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list     && apt-get update && apt-get install -y --no-install-recommends     python3 libcap2-bin openssh-server     && rm -rf /var/lib/apt/lists/*     && useradd -m -s /bin/bash lowpriv     && echo 'lowpriv:lowpriv123' | chpasswd     && echo 'root:toor' | chpasswd     && mkdir -p /var/run/sshd
# 漏洞配置: cap_setuid 赋予 python3 "改 UID" 能力
# 注意: /usr/bin/python3 是 symlink, 必须对真实二进制 python3.8 设置
RUN setcap cap_setuid+ep /usr/bin/python3.8
CMD ["/usr/sbin/sshd", "-D"]
