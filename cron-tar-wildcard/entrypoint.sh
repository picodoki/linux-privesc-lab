#!/bin/bash
# 启动时配置: root 的 tar 备份任务 (在 lowpriv 可写的 /tmp/backup 目录执行 *)
cat > /usr/local/bin/tar-backup.sh <<'EOF'
#!/bin/bash
cd /tmp/backup && tar czf /tmp/backup.tar.gz *
EOF
chmod 755 /usr/local/bin/tar-backup.sh
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/tar-backup.sh") | crontab -
service cron start
service ssh start
tail -f /dev/null
