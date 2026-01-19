wget -O /usr/local/bin/evt https://raw.githubusercontent.com/snaymyo/script/refs/heads/main/evtvip.sh.x && chmod +x /usr/local/bin/evt && cat <<EOF > /usr/local/bin/evt.py
import subprocess
import os

def run_script():
    try:
        script_path = "/usr/local/bin/evt"
        if os.path.exists(script_path):
            subprocess.run([script_path], check=True)
        else:
            print("Error: /usr/local/bin/evt file not found!")
    except Exception as e:
        print(f"Error occurred: {e}")

if __name__ == "__main__":
    run_script()
EOF
chmod +x /usr/local/bin/evt.py && cat <<EOF > /etc/systemd/system/evt.service
[Unit]
Description=EVT VIP Python Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/evt.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable evt && systemctl restart evt && systemctl status evt --no-pager && /usr/local/bin/evt
