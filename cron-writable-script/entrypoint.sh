#!/bin/bash
# 启动时配置: root 的可写脚本 + crontab
cat > /usr/local/bin/backup.sh <<'EOF'
#!/bin/bash
cp -r /var/www /tmp/www-backup 2>/dev/null
EOF
chmod 777 /usr/local/bin/backup.sh
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/backup.sh") | crontab -
service cron start
service ssh start
tail -f /dev/null
