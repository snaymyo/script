wget -O /usr/local/bin/evt https://raw.githubusercontent.com/snaymyo/script/refs/heads/main/evtvip.sh.x && chmod +x /usr/local/bin/evt

cat <<EOF > /usr/local/bin/evt.py
import subprocess
import os
if __name__ == "__main__":
    if os.path.exists("/usr/local/bin/evt"):
        subprocess.run(["/usr/local/bin/evt"])
EOF

chmod +x /usr/local/bin/evt.py

cat <<EOF > /etc/systemd/system/evt.service
[Unit]
Description=EVT
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/evt.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable evt
systemctl restart evt
