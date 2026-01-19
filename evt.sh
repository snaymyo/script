#!/bin/bash

# 1. လိုအပ်တဲ့ script ကို download ဆွဲပြီး permission ပေးမယ်
echo "Downloading evt script..."
wget -O /usr/local/bin/evt https://raw.githubusercontent.com/snaymyo/script/refs/heads/main/evtvip.sh.x && chmod +x /usr/local/bin/evt

# 2. evt.py ဖိုင်ကို တည်ဆောက်မယ်
echo "Creating evt.py..."
cat <<EOF > /usr/local/bin/evt.py
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

# 3. evt.py ကို permission ပေးမယ်
chmod +x /usr/local/bin/evt.py

# 4. Systemd Service ဖန်တီးမယ်
echo "Setting up systemd service..."
cat <<EOF > /etc/systemd/system/evt.service
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

# 5. Service ကို စတင် (Start) လုပ်မယ်
echo "Restarting service..."
systemctl daemon-reload
systemctl enable evt
systemctl restart evt

# 6. status ကို စစ်ဆေးမယ် (Pager မပါဘဲ အတိုချုံးပြပါမယ်)
echo "Checking service status..."
sleep 2
systemctl status evt --no-pager

# 7. Panel ကို တိုက်ရိုက်ဖွင့်ပေးခြင်း
echo "Entering EVT Panel..."
sleep 1
/usr/local/bin/evt
