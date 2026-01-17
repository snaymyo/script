#!/bin/bash

# အရောင်သတ်မှတ်ချက်များ
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Root Check
[[ "$(whoami)" != "root" ]] && { echo -e "${RED}Error: Root user ဖြင့်သာ run ပါ။${NC}"; exit 1; }

# --- လက်ရှိ Port များကို ဖမ်းယူပြသရန် Function များ ---
get_ssh_ports() { grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}' | xargs || echo "22"; }

get_dropbear_ports() { 
    p1=$(grep "DROPBEAR_PORT" /etc/default/dropbear 2>/dev/null | cut -d'=' -f2 | sed 's/"//g')
    p2=$(grep "DROPBEAR_EXTRA_ARGS" /etc/default/dropbear 2>/dev/null | grep -oE "\-p [0-9]+" | awk '{print $2}' | xargs)
    echo "$p1 $p2"
}

get_squid_ports() { grep -i "^http_port" /etc/squid/squid.conf 2>/dev/null | awk '{print $2}' | xargs || echo "None"; }

get_ws_port() {
    if [[ -f "/etc/systemd/system/ws.service" ]]; then
        grep "ExecStart" /etc/systemd/system/ws.service | grep -oE '[0-9]+$' || echo "None"
    else
        echo "None"
    fi
}

# SSL Tunnel port များကို ဖမ်းယူရန်
get_stunnel_ports() {
    if [[ -f "/etc/stunnel/stunnel.conf" ]]; then
        grep -i "^accept" /etc/stunnel/stunnel.conf | cut -d'=' -f2 | xargs || echo "None"
    else
        echo "None"
    fi
}

# --- UI Header ---
header() {
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "              ${WHITE}CONNECTION MODE MANAGER${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}SERVICE:${NC} ${YELLOW}OPENSSH PORT:${NC} $(get_ssh_ports)"
    echo -e "${GREEN}SERVICE:${NC} ${YELLOW}PROXY SOCKS PORT:${NC} $(get_ws_port)"
    echo -e "${GREEN}SERVICE:${NC} ${YELLOW}DROPBEAR PORT:${NC} $(get_dropbear_ports)"
    echo -e "${GREEN}SERVICE:${NC} ${YELLOW}SQUID PORT:${NC} $(get_squid_ports)"
    echo -e "${GREEN}SERVICE:${NC} ${YELLOW}SSL TUNNEL PORT:${NC} $(get_stunnel_ports)"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# --- Management Functions ---

# 01 - SSH
m_ssh() {
    header
    echo -e "${CYAN}[01] Add SSH Port${NC}"
    echo -e "${CYAN}[02] Remove SSH Port${NC}"
    read -p "Option: " opt
    if [[ $opt == "1" ]]; then
        read -p "Port: " p
        echo "Port $p" >> /etc/ssh/sshd_config && systemctl restart ssh
    elif [[ $opt == "2" ]]; then
        read -p "Port: " p
        sed -i "/Port $p/d" /etc/ssh/sshd_config && systemctl restart ssh
    fi
}

# 02 - Squid
m_squid() {
    header
    echo -e "${CYAN}[01] Add Squid Port${NC}"
    echo -e "${CYAN}[02] Remove Squid Port${NC}"
    read -p "Option: " opt
    if [[ $opt == "1" ]]; then
        read -p "Port: " p
        echo "http_port $p" >> /etc/squid/squid.conf && systemctl restart squid
    elif [[ $opt == "2" ]]; then
        read -p "Port: " p
        sed -i "/http_port $p/d" /etc/squid/squid.conf && systemctl restart squid
    fi
}

# 03 - Dropbear
m_dropbear() {
    header
    echo -e "${CYAN}[01] Change Main Port${NC}"
    echo -e "${CYAN}[02] Add Extra Port (-p)${NC}"
    read -p "Option: " opt
    if [[ $opt == "1" ]]; then
        read -p "Port: " p
        sed -i "s/DROPBEAR_PORT=.*/DROPBEAR_PORT=$p/" /etc/default/dropbear && systemctl restart dropbear
    elif [[ $opt == "2" ]]; then
        read -p "Port: " p
        args=$(grep "DROPBEAR_EXTRA_ARGS" /etc/default/dropbear | cut -d'"' -f2)
        sed -i "s/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS=\"$args -p $p\"/" /etc/default/dropbear && systemctl restart dropbear
    fi
}

# 05 - Proxy Socks
m_ws() {
    header
    echo -e "${CYAN}Change Proxy Socks (WebSocket) Port${NC}"
    read -p "Enter New Port: " p
    if [[ -f "/etc/systemd/system/ws.service" ]]; then
        sed -i "s/[0-9]\{2,5\}/$p/g" /etc/systemd/system/ws.service
        systemctl daemon-reload && systemctl restart ws
        echo -e "${GREEN}Proxy Socks Port changed to $p${NC}"; sleep 1
    fi
}

# 06 - SSL TUNNEL (Stunnel4) အသစ်ထည့်သွင်းခြင်း
m_ssl() {
    header
    echo -e "${CYAN}[01] Add SSL Port${NC}"
    echo -e "${CYAN}[02] Remove SSL Port${NC}"
    read -p "Option: " opt
    if [[ $opt == "1" ]]; then
        read -p "Listen Port (SSL Port): " p
        read -p "Internal Port (Connect to - e.g. 22 or 442): " ip
        # Config ထဲသို့ အသစ်ထည့်ခြင်း
        echo -e "\n[SSL_$p]\naccept = $p\nconnect = 127.0.0.1:$ip" >> /etc/stunnel/stunnel.conf
        systemctl restart stunnel4
        echo -e "${GREEN}SSL Port $p Added successfully!${NC}"; sleep 1
    elif [[ $opt == "2" ]]; then
        read -p "Enter SSL Port to Remove: " p
        # Port block တစ်ခုလုံးကို ရှာပြီး ဖျက်ခြင်း
        sed -i "/\[SSL_$p\]/,+2d" /etc/stunnel/stunnel.conf
        # တခြား format နဲ့ရှိနေရင် accept line ကိုပါ ရှာဖျက်မယ်
        sed -i "/accept = $p/,+1d" /etc/stunnel/stunnel.conf
        systemctl restart stunnel4
        echo -e "${RED}SSL Port $p Removed!${NC}"; sleep 1
    fi
}

# --- Main Menu ---
while true; do
    header
    echo -e "${YELLOW}[01]${NC} • OPENSSH ${BLUE}♦${NC}"
    echo -e "${YELLOW}[02]${NC} • SQUID PROXY ${RED}○${NC}"
    echo -e "${YELLOW}[03]${NC} • DROPBEAR ${BLUE}♦${NC}"
    echo -e "${YELLOW}[04]${NC} • OPENVPN ${RED}○${NC}"
    echo -e "${YELLOW}[05]${NC} • PROXY SOCKS ${BLUE}♦${NC}"
    echo -e "${YELLOW}[06]${NC} • SSL TUNNEL ${RED}○${NC}"
    echo -e "${YELLOW}[07]${NC} • SSLH MULTIPLEX ${RED}○${NC}"
    echo -e "${YELLOW}[08]${NC} • CHISEL ${RED}○${NC}"
    echo -e "${YELLOW}[09]${NC} • SLOWDNS ${RED}○${NC}"
    echo -e "${YELLOW}[10]${NC} • COME BACK ${CYAN}<<<${NC}"
    echo -e "${YELLOW}[00]${NC} • GET OUT ${CYAN}<<<${NC}"
    echo -e ""
    read -p "WHAT DO YOU WANT TO DO ?? : " action

    case $action in
        1|01) m_ssh ;;
        2|02) m_squid ;;
        3|03) m_dropbear ;;
        5|05) m_ws ;;
        6|06) m_ssl ;;
        0|00) exit 0 ;;
        *) echo -e "${RED}Invalid!${NC}"; sleep 1 ;;
    esac
done
