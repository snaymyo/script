#!/bin/bash

# --- ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo -e "\033[0;31mError: Root user ဖြင့်သာ run ပါ။ (sudo su ရိုက်ပါ)\033[0m"
   exit 1
fi

# --- AUTOMATIC SHORTCUT SETUP ---
# ဘယ်အချိန်ဖြစ်ဖြစ် evt ရိုက်ရင် ပေါ်အောင်လုပ်ပေးတာ
if [[ "$0" != "/usr/local/bin/evt" ]]; then
    cp "$0" /usr/local/bin/evt
    chmod +x /usr/local/bin/evt
    ln -sf /usr/local/bin/evt /usr/bin/evt &> /dev/null
fi

# --- DEPENDENCY CHECK ---
if ! command -v netstat &> /dev/null || ! command -v wget &> /dev/null || ! command -v curl &> /dev/null; then
    apt update -y &> /dev/null
    apt install net-tools wget curl lsb-release -y &> /dev/null
fi

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

# --- INITIAL SETUP FUNCTION ---
do_setup() {
    clear
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}           -- DOMAIN & NS CONFIGURATION --${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    read -p " ◇ Enter your DOMAIN (Default: evtvip.com): " input_dom
    read -p " ◇ Enter your NAMESERVER (Default: ns.evtvip.com): " input_ns
    [ -z "$input_dom" ] && input_dom="evtvip.com"
    [ -z "$input_ns" ] && input_ns="ns.evtvip.com"
    
    echo "DOMAIN=\"$input_dom\"" > "$CONFIG_FILE"
    echo "NS_DOMAIN=\"$input_ns\"" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    source "$CONFIG_FILE"
    echo -e "${GREEN}Configuration saved successfully!${NC}"
    sleep 1
}

# Config ဖိုင်မရှိရင် setup အရင်လုပ်မယ်
if [ ! -f "$CONFIG_FILE" ]; then
    do_setup
fi
source "$CONFIG_FILE"

# --- SYSTEM INFO GATHERING ---
get_system_info() {
    OS_NAME=$(lsb_release -ds 2>/dev/null | cut -c1-15 || echo "Ubuntu/Debian")
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
    printf " ${CYAN}│${NC} %-15s │ %-10s │ %-12s │ %-26s │\n" "Username" "Password" "Status" "Expiry Date"
    echo -e "${CYAN}├─────────────────┼────────────┼──────────────┼────────────────────────────┤${NC}"
    while IFS=: read -r u_name _ _ _ _ _ u_shell; do
        if [[ "$u_shell" == "/bin/false" ]]; then
            pass_find=$(grep -w "^$u_name" "$USER_DB" | cut -d: -f2); [ -z "$pass_find" ] && pass_find="******"
            exp=$(chage -l "$u_name" 2>/dev/null | grep "Account expires" | cut -d: -f2 | sed 's/ //')
            status_fmt=$(netstat -tnp 2>/dev/null | grep sshd | grep ESTABLISHED | grep -w "$u_name" &>/dev/null && echo -e "${GREEN}Online${NC}" || echo -e "${RED}Offline${NC}")
            printf " ${CYAN}│${NC} %-15s ${CYAN}│${NC} %-10s ${CYAN}│${NC} %-21s ${CYAN}│${NC} %-26s ${CYAN}│${NC}\n" "$u_name" "$pass_find" "$status_fmt" "$exp"
        fi
    done < /etc/passwd
    echo -e "${CYAN}└─────────────────┴────────────┴──────────────┴────────────────────────────┘${NC}"
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
            read -p "Password: " pass; read -p "Days: " days; read -p "Limit: " user_limit
            exp_date=$(date -d "+$days days" +"%Y-%m-%d")
            useradd -e $exp_date -M -s /bin/false $user; echo "$user:$pass" | chpasswd
            echo "$user hard maxlogins $user_limit" >> /etc/security/limits.conf
            echo "$user:$pass" >> "$USER_DB"
            echo -e "${GREEN}User Created Successfully!${NC}"; sleep 2 ;;
        2|02)
            user="test_$(head /dev/urandom | tr -dc 0-9 | head -c 4)"; pass="123"; user_limit="1"
            exp_date=$(date -d "+1 days" +"%Y-%m-%d")
            useradd -e $exp_date -M -s /bin/false $user; echo "$user:$pass" | chpasswd
            echo "$user:$pass" >> "$USER_DB"
            echo -e "${GREEN}Test User Created!${NC}"; sleep 2 ;;
        3|03) display_user_table; read -p "Username to REMOVE: " user; userdel -f $user; sed -i "/^$user:/d" "$USER_DB"; echo -e "${RED}User Removed!${NC}"; sleep 1 ;;
        4|04) display_user_table; read -p "Press Enter to return..." ;;
        10) 
            rm -f "$CONFIG_FILE"
            do_setup # Setup ကို တိုက်ရိုက် ပြန်ခေါ်မယ်
            ;;
        11) bash <(wget -qO- raw.githubusercontent.com/alfainternet/SSHPLUS/master/ssh-plus) ;;
        0|00) clear; exit 0 ;;
        *) sleep 1 ;;
    esac
done
