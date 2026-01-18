#!/bin/bash

# --- DEPENDENCY CHECK ---
if ! command -v netstat &> /dev/null || ! command -v wget &> /dev/null; then
    apt update -y &> /dev/null
    apt install net-tools wget -y &> /dev/null
fi

# --- AUTOMATIC SHORTCUT SETUP ---
SCRIPT_PATH=$(readlink -f "$0")
ln -sf "$SCRIPT_PATH" /usr/local/bin/evt &> /dev/null
chmod +x /usr/local/bin/evt &> /dev/null

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BLUE='\033[1;34m'
NC='\033[0m'

# --- CONFIGURATION & DATABASE ---
CONFIG_FILE="/etc/evt_config"
USER_DB="/etc/evt_users.db"
[ ! -f "$USER_DB" ] && touch "$USER_DB"

# --- INITIAL SETUP ---
if [ ! -f "$CONFIG_FILE" ]; then
    clear
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}           -- INITIAL SERVER SETUP --${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    read -p " ◇ Enter your DOMAIN (Default: evtvip.com): " input_dom
    read -p " ◇ Enter your NAMESERVER (Default: ns.evtvip.com): " input_ns
    [ -z "$input_dom" ] && input_dom="evtvip.com"
    [ -z "$input_ns" ] && input_ns="ns.evtvip.com"
    echo "DOMAIN=\"$input_dom\"" > "$CONFIG_FILE"
    echo "NS_DOMAIN=\"$input_ns\"" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
fi
source "$CONFIG_FILE"

# --- SYSTEM INFO GATHERING ---
get_system_info() {
    OS_NAME=$(lsb_release -ds 2>/dev/null | cut -c1-15 || echo "Ubuntu 20.04")
    UPTIME_FULL=$(uptime -p | sed 's/up //; s/ hours\?/h/; s/ minutes\?/m/; s/ day\(s\)\?/d/' | cut -c1-15)
    RAM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
    RAM_USED_PERC=$(free | grep Mem | awk '{printf("%.2f%%", $3/$2*100)}')
    CPU_CORES=$(nproc)
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{printf("%.2f%%", $2 + $4)}')
    TOTAL_USERS=$(grep -c /bin/false /etc/passwd)
    ONLINE_USERS=$(netstat -tnp 2>/dev/null | grep sshd | grep ESTABLISHED | wc -l)
    
    EXPIRED_USERS=0
    CURRENT_SEC=$(date +%s)
    while IFS=: read -r u_name _ _ _ _ _ u_shell; do
        if [[ "$u_shell" == "/bin/false" ]]; then
            EXP_D=$(chage -l "$u_name" | grep "Account expires" | cut -d: -f2)
            if [[ "$EXP_D" != " never" && -n "$EXP_D" ]]; then
                EXP_S=$(date -d "$EXP_D" +%s 2>/dev/null)
                [[ $EXP_S -le $CURRENT_SEC ]] && ((EXPIRED_USERS++))
            fi
        fi
    done < /etc/passwd
}

get_slowdns_key() {
    if [ -f "/etc/dnstt/server.pub" ]; then
        DNS_PUB_KEY=$(cat "/etc/dnstt/server.pub" | tr -d '\n\r ')
    else
        DNS_PUB_KEY=$(find /etc/dnstt -name "*.pub" 2>/dev/null | xargs cat 2>/dev/null | head -n 1 | tr -d '\n\r ')
    fi
    [ -z "$DNS_PUB_KEY" ] && DNS_PUB_KEY="Not Found"
}

get_ports() {
    SSH_PORT=$(netstat -tunlp 2>/dev/null | grep sshd | grep LISTEN | awk '{print $4}' | cut -d: -f2 | xargs | sed 's/ /, /g'); [ -z "$SSH_PORT" ] && SSH_PORT="22"
    DROPBEAR_PORT=$(netstat -tunlp 2>/dev/null | grep dropbear | grep LISTEN | awk '{print $4}' | cut -d: -f2 | xargs | sed 's/ /, /g'); [ -z "$DROPBEAR_PORT" ] && DROPBEAR_PORT="None"
    STUNNEL_PORT=$(netstat -tunlp 2>/dev/null | grep stunnel | grep LISTEN | awk '{print $4}' | cut -d: -f2 | xargs | sed 's/ /, /g'); [ -z "$STUNNEL_PORT" ] && STUNNEL_PORT="None"
    SQUID_PORT=$(netstat -tunlp 2>/dev/null | grep squid | grep LISTEN | awk '{print $4}' | cut -d: -f2 | xargs | sed 's/ /, /g'); [ -z "$SQUID_PORT" ] && SQUID_PORT="None"
    WS_PORT=$(netstat -tunlp 2>/dev/null | grep -E 'python|node|ws' | grep LISTEN | awk '{print $4}' | cut -d: -f2 | xargs | sed 's/ /, /g'); [ -z "$WS_PORT" ] && WS_PORT="80, 8880"
    OHP_PORT=$(netstat -tunlp 2>/dev/null | grep ohp | grep LISTEN | awk '{print $4}' | cut -d: -f2 | xargs | sed 's/ /, /g'); [ -z "$OHP_PORT" ] && OHP_PORT="None"
    OVPN_TCP=$(netstat -tunlp 2>/dev/null | grep openvpn | grep tcp | grep LISTEN | awk '{print $4}' | cut -d: -f2 | xargs | sed 's/ /, /g'); [ -z "$OVPN_TCP" ] && OVPN_TCP="1194"
    OVPN_UDP=$(netstat -tunlp 2>/dev/null | grep openvpn | grep udp | awk '{print $4}' | cut -d: -f2 | xargs | sed 's/ /, /g'); [ -z "$OVPN_UDP" ] && OVPN_UDP="1194"
}

draw_dashboard() {
    get_system_info
    clear
    echo -e " ${CYAN}┌──────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e " ${CYAN}│${NC}  ${BLUE}◇ SYSTEM INFO${NC}             ${BLUE}◇ RAM & CPU${NC}               ${BLUE}◇ STATUS${NC}         ${CYAN}│${NC}"
    printf " ${CYAN}│${NC}  ${RED}OS:${NC} %-16s  ${RED}RAM:${NC} %-16s  ${RED}Cores:${NC} %-10s ${CYAN}│${NC}\n" "$OS_NAME" "$RAM_TOTAL" "$CPU_CORES"
    printf " ${CYAN}│${NC}  ${RED}UP:${NC} %-16s  ${RED}CPU:${NC} %-16s  ${RED}RAM%%:${NC} %-10s  ${CYAN}│${NC}\n" "$UPTIME_FULL" "$CPU_LOAD" "$RAM_USED_PERC"
    echo -e " ${CYAN}├──────────────────────────────────────────────────────────────────────────┤${NC}"
    printf " ${CYAN}│${NC}  ${GREEN}ONLINE:${NC} %-14s  ${RED}EXPIRED:${NC} %-14s  ${YELLOW}TOTAL:${NC} %-11s ${CYAN}│${NC}\n" "$ONLINE_USERS" "$EXPIRED_USERS" "$TOTAL_USERS"
    echo -e " ${CYAN}└──────────────────────────────────────────────────────────────────────────┘${NC}"
}

display_user_table() {
    clear
    echo -e "${CYAN}┌─────────────────┬────────────┬──────────────┬────────────────────────────┐${NC}"
    echo -e " ${CYAN}│${NC}                      ${WHITE}--- CURRENT SYSTEM USERS ---${NC}                        ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────┼────────────┼──────────────┼────────────────────────────┤${NC}"
    printf " ${CYAN}│${NC} ${YELLOW}%-15s${NC} ${CYAN}│${NC} ${YELLOW}%-10s${NC} ${CYAN}│${NC} ${YELLOW}%-12s${NC} ${CYAN}│${NC} ${YELLOW}%-26s${NC} ${CYAN}│${NC}\n" "Username" "Password" "Status" "Expiry Date"
    echo -e "${CYAN}├─────────────────┼────────────┼──────────────┼────────────────────────────┤${NC}"
    
    while IFS=: read -r u_name _ _ _ _ _ u_shell; do
        if [[ "$u_shell" == "/bin/false" ]]; then
            pass_find=$(grep -w "^$u_name" "$USER_DB" | cut -d: -f2)
            [ -z "$pass_find" ] && pass_find="******"
            exp=$(chage -l "$u_name" 2>/dev/null | grep "Account expires" | cut -d: -f2 | sed 's/ //')
            [ -z "$exp" ] || [[ "$exp" == "never" ]] && exp="No Expiry"
            
            if netstat -tnp 2>/dev/null | grep sshd | grep ESTABLISHED | grep -w "$u_name" &>/dev/null; then
                status_fmt="${GREEN}Online${NC}"
                pad="      "
            else
                status_fmt="${RED}Offline${NC}"
                pad="     "
            fi
            printf " ${CYAN}│${NC} %-15s ${CYAN}│${NC} %-10s ${CYAN}│${NC} %s%s ${CYAN}│${NC} %-26s ${CYAN}│${NC}\n" "$u_name" "$pass_find" "$status_fmt" "$pad" "$exp"
        fi
    done < /etc/passwd
    echo -e "${CYAN}└─────────────────┴────────────┴──────────────┴────────────────────────────┘${NC}"
    echo ""
}

show_details() {
    clear
    get_slowdns_key
    get_ports
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}           -- SSH & VPN ACCOUNT DETAILS --${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    printf " ${WHITE}%-15s :${NC} ${GREEN}%s${NC}\n" "Username" "$user"
    printf " ${WHITE}%-15s :${NC} ${GREEN}%s${NC}\n" "Password" "$pass"
    printf " ${WHITE}%-15s :${NC} ${GREEN}%s${NC}\n" "Expired Date" "$exp_date"
    printf " ${WHITE}%-15s :${NC} ${GREEN}%s Device(s)${NC}\n" "Limit" "$user_limit"
    printf " ${WHITE}%-15s :${NC} ${YELLOW}%s${NC}\n" "Domain" "$DOMAIN"
    printf " ${WHITE}%-15s :${NC} ${YELLOW}%s${NC}\n" "NS Domain" "$NS_DOMAIN"
    echo -e " Publickey       : ${CYAN}$DNS_PUB_KEY${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    printf " %-16s: ${WHITE}%s${NC}\n" "SSH Port" "$SSH_PORT"
    printf " %-16s: ${WHITE}%s${NC}\n" "SSH Websocket" "$WS_PORT"
    printf " %-16s: ${WHITE}%s${NC}\n" "Squid Port" "$SQUID_PORT"
    printf " %-16s: ${WHITE}%s${NC}\n" "Dropbear Port" "$DROPBEAR_PORT"
    printf " %-16s: ${WHITE}%s${NC}\n" "Stunnel Port" "$STUNNEL_PORT"
    printf " %-16s: ${WHITE}%s${NC}\n" "OVPN TCP/UDP" "$OVPN_TCP / $OVPN_UDP"
    echo -e "${CYAN}=====================================================${NC}"
    echo ""
    read -p "Press Enter to return to menu..."
}

# --- MAIN LOOP ---
while true; do
    draw_dashboard
    echo ""
    echo -e " ${YELLOW}[01]${NC} CREATE USER          ${YELLOW}[05]${NC} CHANGE USERNAME"
    echo -e " ${YELLOW}[02]${NC} CREATE TEST USER     ${YELLOW}[06]${NC} CHANGE PASSWORD"
    echo -e " ${YELLOW}[03]${NC} REMOVE USER          ${YELLOW}[07]${NC} CHANGE DATE"
    echo -e " ${YELLOW}[04]${NC} USER INFO (FULL)     ${YELLOW}[08]${NC} CHANGE LIMIT"
    echo -e " ${YELLOW}[09]${NC} SlowDns Install      ${YELLOW}[10]${NC} RESET DOMAIN/NS"
    echo -e " ${YELLOW}[11]${NC} OPEN PORTS (SSHPlus) ${YELLOW}[00]${NC} EXIT"
    echo ""
    read -p " ◇ Select Option: " opt

    case $opt in
        1|01)
            read -p "Username: " user
            while id "$user" &>/dev/null; do
                echo -e "${RED}Already Name${NC}"
                read -p "Create New Name: " user
            done
            read -p "Password: " pass; read -p "Days: " days; read -p "Limit: " user_limit
            exp_date=$(date -d "+$days days" +"%Y-%m-%d")
            useradd -e $exp_date -M -s /bin/false $user; echo "$user:$pass" | chpasswd
            echo "$user hard maxlogins $user_limit" >> /etc/security/limits.conf
            echo "$user:$pass" >> "$USER_DB"
            show_details ;;
        2|02)
            user="test_$(head /dev/urandom | tr -dc 0-9 | head -c 4)"; pass="123"; user_limit="1"
            exp_date=$(date -d "+1 days" +"%Y-%m-%d")
            useradd -e $exp_date -M -s /bin/false $user; echo "$user:$pass" | chpasswd
            echo "$user:$pass" >> "$USER_DB"
            show_details ;;
        3|03) display_user_table; read -p "Username to REMOVE: " user; userdel -f $user; sed -i "/^$user:/d" "$USER_DB"; sed -i "/$user hard maxlogins/d" /etc/security/limits.conf; echo -e "${RED}User Removed!${NC}"; sleep 1 ;;
        4|04) display_user_table; read -p "Press Enter to return..." ;;
        5|05) display_user_table; read -p "Old Username: " old_user; read -p "New Username: " new_user; usermod -l $new_user $old_user; sed -i "s/^$old_user:/$new_user:/" "$USER_DB"; sed -i "s/$old_user hard maxlogins/$new_user hard maxlogins/" /etc/security/limits.conf; echo -e "${GREEN}Username Changed!${NC}"; sleep 1 ;;
        6|06) display_user_table; read -p "Username: " user; read -p "New Password: " pass; echo "$user:$pass" | chpasswd; sed -i "s/^$user:.*/$user:$pass/" "$USER_DB"; echo -e "${GREEN}Password Updated!${NC}"; sleep 1 ;;
        7|07) display_user_table; read -p "Username: " user; read -p "New Expiry Date (YYYY-MM-DD): " exp_date; usermod -e $exp_date $user; echo -e "${GREEN}Expiry Date Updated!${NC}"; sleep 1 ;;
        8|08) display_user_table; read -p "Username: " user; read -p "New Login Limit: " user_limit; sed -i "/$user hard maxlogins/d" /etc/security/limits.conf; echo "$user hard maxlogins $user_limit" >> /etc/security/limits.conf; echo -e "${GREEN}Limit Updated!${NC}"; sleep 1 ;;
        9|09) bash <(curl -Ls https://raw.githubusercontent.com/bugfloyd/dnstt-deploy/main/dnstt-deploy.sh); read -p "Press Enter to return..." ;;
        10) 
            rm -f "$CONFIG_FILE"
            echo -e "${RED}Config Reset! Restarting...${NC}"
            sleep 1
            exec bash "$0"
            ;;
        11)
            clear
            echo -e "${YELLOW}Launching Port Manager (SSHPlus)...${NC}"
            bash <(wget -qO- raw.githubusercontent.com/alfainternet/SSHPLUS/master/ssh-plus)
            echo ""
            read -p "Press Enter to return to main menu..."
            ;;
        0|00) exit 0 ;;
        *) sleep 1 ;;
    esac
done
