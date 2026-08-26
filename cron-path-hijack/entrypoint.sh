#!/bin/bash
# 启动时配置: root 脚本先把用户目录放进 PATH, 再调用 tar (不带绝对路径)
cat > /usr/local/bin/path-backup.sh <<'EOF'
#!/bin/bash
export PATH=/home/lowpriv/bin:$PATH
tar czf /tmp/pathbk.tar.gz /var/log 2>/dev/null
EOF
chmod 755 /usr/local/bin/path-backup.sh
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/path-backup.sh") | crontab -
service cron start
service ssh start
tail -f /dev/null
