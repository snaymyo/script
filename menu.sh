#!/bin/bash

# --- AUTO INSTALL AS 'evt' COMMAND ---
if [[ "$0" != "/usr/local/bin/evt" ]]; then
    cp "$0" /usr/local/bin/evt
    chmod +x /usr/local/bin/evt
    echo -e "\e[1;32mCommand 'evt' has been registered successfully!\e[0m"
fi

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- CONFIGURATION STORAGE ---
CONFIG_FILE="/etc/evt_config"
if [ ! -f "$CONFIG_FILE" ]; then
    clear
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}            FIRST TIME SETUP (ONE-TIME)${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    read -p " ◇ Enter Domain (evtvip.com): " USER_DOMAIN
    read -p " ◇ Enter NS Domain (ns.evtvip.com): " USER_NS_DOMAIN
    [ -z "$USER_DOMAIN" ] && USER_DOMAIN="evtvip.com"
    [ -z "$USER_NS_DOMAIN" ] && USER_NS_DOMAIN="ns.$USER_DOMAIN"
    echo "DOMAIN=\"$USER_DOMAIN\"" > "$CONFIG_FILE"
    echo "NS_DOMAIN=\"$USER_NS_DOMAIN\"" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi
source "$CONFIG_FILE"

# Server Info
IP_ADDR=$(curl -s ifconfig.me)
LOCATION=$(curl -s https://ipapi.co/country_name/)
[ -z "$LOCATION" ] && LOCATION="Unknown"

# --- AUTO SLOWDNS PUBLIC KEY DETECTION ---
get_slowdns_key() {
    local key_prefix=$(echo "$NS_DOMAIN" | sed 's/\./_/g')
    if [ -f "/etc/dnstt/server.pub" ]; then DNS_PUB_KEY=$(cat "/etc/dnstt/server.pub" | tr -d '\n\r ');
    elif [ -f "/etc/dnstt/${key_prefix}_server.pub" ]; then DNS_PUB_KEY=$(cat "/etc/dnstt/${key_prefix}_server.pub" | tr -d '\n\r ');
    else DNS_PUB_KEY=$(find /etc/dnstt -name "*.pub" 2>/dev/null | xargs cat 2>/dev/null | head -n 1 | tr -d '\n\r '); fi
    [ -z "$DNS_PUB_KEY" ] && DNS_PUB_KEY="Not Found"
}

# --- AUTO PORT DETECTION ---
get_ports() {
    SSH_PORT=$(netstat -tulnp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | sort -nu | xargs | sed 's/ /, /g')
    DROPBEAR_PORT=$(netstat -tulnp | grep dropbear | awk '{print $4}' | awk -F: '{print $NF}' | sort -nu | xargs | sed 's/ /, /g')
    STUNNEL_PORT=$(netstat -tulnp | grep stunnel | awk '{print $4}' | awk -F: '{print $NF}' | sort -nu | xargs | sed 's/ /, /g')
    SQUID_PORT=$(netstat -tulnp | grep squid | awk '{print $4}' | awk -F: '{print $NF}' | sort -nu | xargs | sed 's/ /, /g')
    OVPN_PORT=$(netstat -tulnp | grep openvpn | awk '{print $4}' | awk -F: '{print $NF}' | sort -nu | xargs | sed 's/ /, /g')
    WS_PORT=$(netstat -tulnp | grep -E 'python|ws|proxy' | grep ':80 ' | awk '{print $4}' | awk -F: '{print $NF}' | sort -nu | xargs | sed 's/ /, /g')
    [ -z "$WS_PORT" ] && WS_PORT="80"
}

# --- FINAL ACCOUNT DETAILS OUTPUT ---
show_details() {
    get_ports
    get_slowdns_key
    clear
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${RED}               -- ACCOUNT DETAILS --${NC}"
    echo -e " "
    echo -e " Username: ${GREEN}$user${NC}"
    echo -e " Password: ${GREEN}$pass${NC}"
    echo -e " Limit   : ${GREEN}${user_limit:-1} Device(s)${NC}"
    echo -e " Created : ${created_date:-Updated}"
    echo -e " Expired : ${exp_date:-N/A}"
    echo -e " "
    echo -e "${RED}               -- SERVER DETAILS --${NC}"
    echo -e " "
    echo -e " IP Address: $IP_ADDR"
    echo -e " Location  : $LOCATION"
    echo -e " Hostname  : $DOMAIN"
    echo -e " "
    echo -e " SSH Port      : ${SSH_PORT:-None}"
    echo -e " Squid Port    : ${SQUID_PORT:-None}"
    echo -e " Dropbear Port : ${DROPBEAR_PORT:-None}"
    echo -e " Stunnel Port  : ${STUNNEL_PORT:-None}"
    echo -e " OVPN Port     : ${OVPN_PORT:-None}"
    echo -e " SSH Websocket : ${WS_PORT:-None}"
    echo -e " "
    echo -e "${RED}               -- SLOWDNS DETAILS --${NC}"
    echo -e " Nameserver    : ${GREEN}$NS_DOMAIN${NC}"
    echo -e " Public Key    : ${CYAN}$DNS_PUB_KEY${NC}"
    echo -e " "
    echo -e "${YELLOW} Websocket Payload:${NC}"
    echo -e " GET / HTTP/1.1[crlf]Host: $DOMAIN [crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${CYAN}=====================================================${NC}"
    echo ""
    read -p "Press Enter to return to menu..."
}

# --- USER INFO FUNCTION (ONLINE/OFFLINE ONLY) ---
show_user_info() {
    clear
    echo -e "${CYAN}===========================================================${NC}"
    echo -e "${RED}                   -- USER INFORMATION --${NC}"
    echo -e "${CYAN}===========================================================${NC}"
    printf "${YELLOW}%-18s | %-12s | %-15s${NC}\n" "  Username" "   Status" "  Expiry Date"
    echo -e "${CYAN}-----------------------------------------------------------${NC}"
    while IFS=: read -r username _ _ _ _ _ shell; do
        if [[ "$shell" == "/bin/false" ]]; then
            # Get Expiry Date
            exp=$(chage -l "$username" | grep "Account expires" | cut -d: -f2 | sed 's/ //')
            [ "$exp" == "never" ] && exp="No Expiry"
            
            # Check Status (Online/Offline)
            is_online=$(netstat -tnp 2>/dev/null | grep sshd | grep ESTABLISHED | grep -w "$username")
            if [ -z "$is_online" ]; then
                status="${RED}Offline${NC}"
            else
                status="${GREEN}Online${NC}"
            fi
            printf "  %-16s | %-21s | %-15s\n" "$username" "$status" "$exp"
        fi
    done < /etc/passwd
    echo -e "${CYAN}===========================================================${NC}"
    echo ""
    read -p "Press Enter to return to menu..."
}

# --- DASHBOARD INFO ---
get_system_info() {
    OS_NAME=$(lsb_release -is 2>/dev/null || echo "Ubuntu")
    OS_VER=$(lsb_release -rs 2>/dev/null || echo "20.04")
    UPTIME=$(uptime -p | sed 's/up //; s/ days/d/; s/ day/d/; s/ hours/h/; s/ hour/h/; s/ minutes/m/; s/ minute/m/')
    RAM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
    RAM_USED_PERC=$(free | grep Mem | awk '{printf("%.2f%%", $3/$2*100)}')
    CPU_CORES=$(nproc)
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 "%"}')
    TOTAL_USERS=$(grep -c /bin/false /etc/passwd)
    ONLINE_USERS=$(netstat -tnp 2>/dev/null | grep sshd | grep ESTABLISHED | wc -l)
}

# --- MAIN LOOP ---
while true; do
    get_system_info
    clear
    echo -e " "
    echo -e "                     ${RED}EVT VIP VPS${NC}"
    echo -e " "
    echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
    printf "│ ${CYAN}◇  SYSTEM${NC}           ${CYAN}◇  RAM MEMORY${NC}        ${CYAN}◇  PROCESSOR${NC}    │\n"
    printf "│ ${RED}OS:${NC} %-14s ${RED}Total:${NC} %-11s ${RED}CPU cores:${NC} %-6s │\n" "$OS_NAME $OS_VER" "$RAM_TOTAL" "$CPU_CORES"
    printf "│ ${RED}Up Time:${NC} %-10s ${RED}In use:${NC} %-10s ${RED}In use:${NC} %-9s │\n" "$UPTIME" "$RAM_USED_PERC" "$CPU_LOAD"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
    printf "│ ${GREEN}◇  Online:${NC} %-9s ${RED}◇  expired: 0${NC}          ${YELLOW}◇  Total:${NC} %-7s │\n" "$ONLINE_USERS" "$TOTAL_USERS"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"
    echo -e ""
    echo -e " ${YELLOW}[01]${NC} ${CYAN}◇${NC} CREATE USER          ${YELLOW}[06]${NC} ${CYAN}◇${NC} CHANGE LIMIT"
    echo -e " ${YELLOW}[02]${NC} ${CYAN}◇${NC} CREATE TEST USER     ${YELLOW}[07]${NC} ${CYAN}◇${NC} CHANGE PASSWORD"
    echo -e " ${YELLOW}[03]${NC} ${CYAN}◇${NC} REMOVE USER          ${YELLOW}[08]${NC} ${CYAN}◇${NC} CHANGE USERNAME"
    echo -e " ${YELLOW}[04]${NC} ${CYAN}◇${NC} USER INFO            ${YELLOW}[09]${NC} ${CYAN}◇${NC} SlowDns install"
    echo -e " ${YELLOW}[05]${NC} ${CYAN}◇${NC} CHANGE DATE          ${YELLOW}[00]${NC} ${CYAN}◇${NC} GET OUT"
    echo -e ""
    read -p " ◇ WHAT DO YOU WANT TO DO ?? : " opt

    case $opt in
        01|1)
            echo -e "\n${CYAN}[ CREATE NEW ACCOUNT ]${NC}"
            read -p "Username: " user; read -p "Password: " pass; read -p "Active Days: " days; read -p "User Limit: " user_limit
            exp_date=$(date -d "+$days days" +"%Y-%m-%d"); created_date=$(date +"%Y-%m-%d")
            useradd -e $exp_date -M -s /bin/false $user; echo "$user:$pass" | chpasswd
            echo "$user hard maxlogins $user_limit" >> /etc/security/limits.conf
            show_details ;;
        02|2)
            user="test_$(head /dev/urandom | tr -dc 0-9 | head -c 4)"; pass="123"; user_limit="1"
            exp_date=$(date -d "+1 days" +"%Y-%m-%d"); created_date=$(date +"%Y-%m-%d")
            useradd -e $exp_date -M -s /bin/false $user; echo "$user:$pass" | chpasswd
            show_details ;;
        03|3)
            echo -e "\n${RED}[ REMOVE USER ]${NC}"; read -p "Enter Username: " user
            userdel -r $user; sed -i "/$user hard maxlogins/d" /etc/security/limits.conf
            echo -e "${RED}User Removed!${NC}"; sleep 2 ;;
        04|4) show_user_info ;;
        05|5)
            read -p "Username: " user; read -p "New Expiry (YYYY-MM-DD): " exp_date
            usermod -e $exp_date $user; echo -e "${GREEN}Date updated!${NC}"; sleep 2 ;;
        07|7)
            read -p "Username: " user; read -p "New Password: " pass
            echo "$user:$pass" | chpasswd; echo -e "${GREEN}Password updated!${NC}"; sleep 2 ;;
        09|9)
            bash <(curl -Ls https://raw.githubusercontent.com/bugfloyd/dnstt-deploy/main/dnstt-deploy.sh) ;;
        00|0) exit 0 ;;
        *) sleep 1 ;;
    esac
done
