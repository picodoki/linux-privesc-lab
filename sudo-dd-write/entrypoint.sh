#!/bin/bash
# 预置: root 的 cron 每分钟执行 backup.sh (dd 覆盖目标)
cat > /usr/local/bin/backup.sh <<'EOF'
#!/bin/bash
echo backup-ok > /tmp/backup.log
EOF
chmod 755 /usr/local/bin/backup.sh
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/backup.sh") | crontab -
service cron start
service ssh start
tail -f /dev/null
