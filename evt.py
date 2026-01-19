# 1. လိုအပ်တဲ့ script ကို အရင် download ဆွဲထားမယ်
wget -O /usr/local/bin/evt https://raw.githubusercontent.com/snaymyo/script/refs/heads/main/evtvip.sh.x && chmod +x /usr/local/bin/evt

# 2. evt.py ဖိုင်ကို တည်ဆောက်မယ်
cat <<EOF > /usr/local/bin/evt.py
import subprocess
import os

def run_script():
    try:
        # မူလ script ကို Python ကနေ ခေါ် run တာဖြစ်ပါတယ်
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

# 4. Systemd Service ကို Python run ဖို့ ပြင်ဆင်မယ်
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

# 5. Service ကို ပြန် restart လုပ်မယ်
systemctl daemon-reload
systemctl enable evt
systemctl restart evt

# status စစ်မယ်
systemctl status evt