#!/bin/bash

# --- Dependencies & Initial Check ---
if ! command -v netstat &> /dev/null; then
    apt update -y &> /dev/null
    apt install net-tools lsb-release python3 screen psmisc lsof curl wget -y &> /dev/null
fi

# Color Definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BLUE='\033[1;34m'
NC='\033[0m'

CONFIG_FILE="/etc/evt_config"
USER_DB="/etc/evt_users.db"
BACKUP_FILE="/root/backup.txt"
RESTORE_FILE="/root/restore.txt"
[ ! -f "$USER_DB" ] && touch "$USER_DB"

# --- Setup Functions ---
do_initial_setup() {
    clear
    echo -e "${CYAN}┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}${YELLOW}           -- INITIAL SERVER SETUP --${NC}${CYAN}            │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────┘${NC}"
    read -p " ◇ Enter your DOMAIN (Default: evtvip.com): " input_dom
    read -p " ◇ Enter your NAMESERVER (Default: ns.evtvip.com): " input_ns
    [ -z "$input_dom" ] && input_dom="evtvip.com"
    [ -z "$input_ns" ] && input_ns="ns.evtvip.com"
    echo "DOMAIN=\"$input_dom\"" > "$CONFIG_FILE"
    echo "NS_DOMAIN=\"$input_ns\"" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    source "$CONFIG_FILE"
}

[ ! -f "$CONFIG_FILE" ] && do_initial_setup
source "$CONFIG_FILE"

check_port() {
    local service=$1
    local result=$(netstat -tunlp 2>/dev/null | grep LISTEN | grep -i "$service" | awk '{print $4}' | sed 's/.*://' | sort -u | xargs)
    [ -z "$result" ] && echo "None" || echo "$result"
}

get_ports() {
    SSH_PORT=$(check_port "sshd")
    WS_PORT=$(netstat -tunlp 2>/dev/null | grep LISTEN | grep -E 'python|node|ws-st|proxy|litespeed|go-ws' | awk '{print $4}' | sed 's/.*://' | sort -u | xargs); [ -z "$WS_PORT" ] && WS_PORT="None"
    SQUID_PORT=$(check_port "squid")
    DROPBEAR_PORT=$(check_port "dropbear")
    STUNNEL_PORT=$(netstat -tunlp 2>/dev/null | grep LISTEN | grep -E 'stunnel|stunnel4' | awk '{print $4}' | sed 's/.*://' | sort -u | xargs); [ -z "$STUNNEL_PORT" ] && STUNNEL_PORT="None"
    OHP_PORT=$(check_port "ohp")
    OVPN_TCP=$(netstat -tunlp 2>/dev/null | grep LISTEN | grep openvpn | grep tcp | awk '{print $4}' | sed 's/.*://' | sort -u | xargs); [ -z "$OVPN_TCP" ] && OVPN_TCP="None"
    OVPN_UDP=$(netstat -tunlp 2>/dev/null | grep udp | grep openvpn | awk '{print $4}' | sed 's/.*://' | sort -u | xargs); [ -z "$OVPN_UDP" ] && OVPN_UDP="None"
    OVPN_SSL="$STUNNEL_PORT"
}

get_slowdns_key_info() {
    if [ -f "/etc/dnstt/server.pub" ]; then
        DNS_PUB_KEY=$(cat "/etc/dnstt/server.pub" 2>/dev/null | tr -d '\n\r ')
    else
        DNS_PUB_KEY=$(find /etc/dnstt -name "*.pub" 2>/dev/null | xargs cat 2>/dev/null | head -n 1 | tr -d '\n\r ')
    fi
    [ -z "$DNS_PUB_KEY" ] && DNS_PUB_KEY="None"
}

# --- Create User Result Table (Publickey Copy Version) ---
show_details() {
    clear
    get_slowdns_key_info
    get_ports
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}${YELLOW}               -- SSH & VPN ACCOUNT DETAILS --${NC}${CYAN}               │${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} %-16s : ${GREEN}%-40s${NC} ${CYAN}│${NC}\n" "Username" "${user:-N/A}"
    printf "${CYAN}│${NC} %-16s : ${GREEN}%-40s${NC} ${CYAN}│${NC}\n" "Password" "${pass:-N/A}"
    printf "${CYAN}│${NC} %-16s : ${GREEN}%-40s${NC} ${CYAN}│${NC}\n" "Expired Date" "${exp_date:-N/A}"
    printf "${CYAN}│${NC} %-16s : ${GREEN}%-40s${NC} ${CYAN}│${NC}\n" "Limit" "${user_limit:-1} Device(s)"
    printf "${CYAN}│${NC} %-16s : ${YELLOW}%-40s${NC} ${CYAN}│${NC}\n" "Domain" "$DOMAIN"
    printf "${CYAN}│${NC} %-16s : ${YELLOW}%-40s${NC} ${CYAN}│${NC}\n" "NS Domain" "$NS_DOMAIN"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} ${WHITE}Publickey (Full Copy):${NC}                                       ${CYAN}│${NC}"
    printf "${CYAN}│${NC} ${CYAN}%-59s${NC} ${CYAN}│${NC}\n" "${DNS_PUB_KEY:0:59}"
    [ ${#DNS_PUB_KEY} -gt 59 ] && printf "${CYAN}│${NC} ${CYAN}%-59s${NC} ${CYAN}│${NC}\n" "${DNS_PUB_KEY:59}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} %-16s : ${WHITE}%-40s${NC} ${CYAN}│${NC}\n" "SSH Port" "$SSH_PORT"
    printf "${CYAN}│${NC} %-16s : ${WHITE}%-40s${NC} ${CYAN}│${NC}\n" "SSH Websocket" "$WS_PORT"
    printf "${CYAN}│${NC} %-16s : ${WHITE}%-40s${NC} ${CYAN}│${NC}\n" "Squid Port" "$SQUID_PORT"
    printf "${CYAN}│${NC} %-16s : ${WHITE}%-40s${NC} ${CYAN}│${NC}\n" "Dropbear Port" "$DROPBEAR_PORT"
    printf "${CYAN}│${NC} %-16s : ${WHITE}%-40s${NC} ${CYAN}│${NC}\n" "Stunnel Port" "$STUNNEL_PORT"
    printf "${CYAN}│${NC} %-16s : ${WHITE}%-40s${NC} ${CYAN}│${NC}\n" "OHP Port" "$OHP_PORT"
    printf "${CYAN}│${NC} %-16s : ${WHITE}%-40s${NC} ${CYAN}│${NC}\n" "OVPN TCP" "$OVPN_TCP"
    printf "${CYAN}│${NC} %-16s : ${WHITE}%-40s${NC} ${CYAN}│${NC}\n" "OVPN UDP" "$OVPN_UDP"
    printf "${CYAN}│${NC} %-16s : ${WHITE}%-40s${NC} ${CYAN}│${NC}\n" "OVPN SSL" "$OVPN_SSL"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
}

# --- System Functions ---
check_user_limits_and_expired() {
    local current_sec=$(date +%s)
    [ ! -s "$USER_DB" ] && return
    while IFS=: read -r u p; do
        [[ -z "$u" || "$u" == "root" ]] && continue
        if ! id "$u" &>/dev/null; then continue; fi
        exp_date_raw=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        if [[ -n "$exp_date_raw" && "$exp_date_raw" != "never" ]]; then
            exp_sec=$(date -d "$exp_date_raw" +%s 2>/dev/null)
            if [[ -n "$exp_sec" && "$exp_sec" -le "$current_sec" ]]; then
                userdel -f "$u" &>/dev/null
                sed -i "/^$u:/d" "$USER_DB"
                sed -i "/$u hard maxlogins/d" /etc/security/limits.conf
                continue
            fi
        fi
        local max_limit=$(grep -E "^$u[[:space:]]+hard[[:space:]]+maxlogins" /etc/security/limits.conf 2>/dev/null | awk '{print $4}' | head -n 1)
        [ -z "$max_limit" ] && max_limit=1
        local session_pids=$(pgrep -u "$u" sshd 2>/dev/null | sort -rn)
        local count=$(echo "$session_pids" | wc -w)
        if [ "$count" -gt "$max_limit" ]; then
            local excess=$((count - max_limit))
            for pid in $(echo "$session_pids" | head -n "$excess"); do
                kill -9 "$pid" &>/dev/null
            done
        fi
    done < "$USER_DB"
}

get_system_info() {
    check_user_limits_and_expired 
    OS_NAME=$(lsb_release -ds 2>/dev/null | cut -c 1-20); [ -z "$OS_NAME" ] && OS_NAME="Ubuntu 20.04"
    UPTIME_VAL=$(uptime -p 2>/dev/null | sed 's/up //; s/ hours\?,/h/; s/ minutes\?/m/; s/ days\?,/d/' | cut -c 1-12)
    RAM_TOTAL=$(free -h 2>/dev/null | grep Mem | awk '{print $2}')
    RAM_USED_PERC=$(free 2>/dev/null | grep Mem | awk '{printf("%.2f%%", $3/$2*100)}')
    CPU_CORES=$(nproc 2>/dev/null); CPU_LOAD=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{printf("%.2f%%", $2 + $4)}')
    TOTAL_USERS=$(wc -l < "$USER_DB" 2>/dev/null)
    ONLINE_USERS=0
    if [ -s "$USER_DB" ]; then
        while IFS=: read -r u p; do
            [[ -z "$u" || "$u" == "root" ]] && continue
            if id "$u" &>/dev/null; then
                count=$(pgrep -u "$u" sshd 2>/dev/null | wc -l)
                ONLINE_USERS=$((ONLINE_USERS + count))
            fi
        done < "$USER_DB"
    fi
}

draw_dashboard() {
    get_system_info
    clear
    echo -e "                     ${RED}EVT SSH Manager${NC}"
    echo -e " ${CYAN}┌──────────────────────────────────────────────────────────────────────────┐${NC}"
    printf " ${CYAN}│${NC}  ${BLUE}%-23s${NC}  ${BLUE}%-23s${NC}  ${BLUE}%-22s${NC} ${CYAN}│${NC}\n" "◇  SYSTEM" "◇  RAM MEMORY" "◇  PROCESS"
    printf " ${CYAN}│${NC}  ${RED}OS:${NC} %-19s  ${RED}Total:${NC} %-16s  ${RED}CPU cores:${NC} %-12s ${CYAN}│${NC}\n" "$OS_NAME" "$RAM_TOTAL" "$CPU_CORES"
    printf " ${CYAN}│${NC}  ${RED}Up Time:${NC} %-14s  ${RED}In use:${NC} %-15s  ${RED}In use:${NC} %-15s ${CYAN}│${NC}\n" "$UPTIME_VAL" "$RAM_USED_PERC" "$CPU_LOAD"
    echo -e " ${CYAN}├──────────────────────────────────────────────────────────────────────────┤${NC}"
    printf " ${CYAN}│${NC}  ${GREEN}◇  Online:${NC} %-12s  ${RED}◇  expired:${NC} %-13s  ${YELLOW}◇  Total:${NC} %-21s ${CYAN}│${NC}\n" "$ONLINE_USERS" "0" "$TOTAL_USERS"
    echo -e " ${CYAN}└──────────────────────────────────────────────────────────────────────────┘${NC}"
}

display_user_table() {
    check_user_limits_and_expired
    clear
    echo -e " ${CYAN}┌─────────────────┬──────────────┬─────────────────────┬─────────────────┐${NC}"
    printf " ${CYAN}│${NC} ${YELLOW}%-15s${NC} ${CYAN}│${NC} ${YELLOW}%-12s${NC} ${CYAN}│${NC} ${YELLOW}%-19s${NC} ${CYAN}│${NC} ${YELLOW}%-15s${NC} ${CYAN}│${NC}\n" "Username" "Password" "Status/Limit" "Expiry Date"
    echo -e " ${CYAN}├─────────────────┼──────────────┼─────────────────────┼─────────────────┤${NC}"
    if [ ! -s "$USER_DB" ]; then
        printf " ${CYAN}│${NC} %-66s ${CYAN}│${NC}\n" "${RED}No created users found.${NC}"
    else
        while IFS=: read -r username pass_find; do
            if id "$username" &>/dev/null; then
                exp_t=$(chage -l "$username" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
                [ -z "$exp_t" ] || [[ "$exp_t" == "never" ]] && exp_t="No Expiry"
                count_on=$(pgrep -u "$username" sshd 2>/dev/null | wc -l)
                u_limit=$(grep -E "^$username[[:space:]]+hard[[:space:]]+maxlogins" /etc/security/limits.conf 2>/dev/null | awk '{print $4}' | head -n 1)
                [ -z "$u_limit" ] && u_limit="1"
                if [ "$count_on" -gt 0 ]; then stat_print="${GREEN}${count_on}/${u_limit} Online${NC}"; else stat_print="${RED}Offline${NC}"; fi
                printf " ${CYAN}│${NC} %-15s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-28b ${CYAN}│${NC} %-15s ${CYAN}│${NC}\n" "$username" "$pass_find" "$stat_print" "$exp_t"
            fi
        done < "$USER_DB"
    fi
    echo -e " ${CYAN}└─────────────────┴──────────────┴─────────────────────┴─────────────────┘${NC}"
}

user_backup() {
    clear
    echo -e "${CYAN}--- TELEGRAM USER BACKUP ---${NC}"
    if [ ! -s "$USER_DB" ]; then echo -e "${RED}No users to backup!${NC}"; sleep 2; return; fi
    > "$BACKUP_FILE"
    while IFS=: read -r u p; do
        [[ -z "$u" || "$u" == "root" ]] && continue
        if ! id "$u" &>/dev/null; then continue; fi
        exp_raw=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        if [[ "$exp_raw" == "never" || -z "$exp_raw" ]]; then exp_f="never"; else exp_f=$(date -d "$exp_raw" +"%Y-%m-%d" 2>/dev/null || echo "never"); fi
        lim=$(grep -E "^$u[[:space:]]+hard[[:space:]]+maxlogins" /etc/security/limits.conf 2>/dev/null | awk '{print $4}' | head -n 1); [ -z "$lim" ] && lim="1"
        echo "$u:$p:$exp_f:$lim" >> "$BACKUP_FILE"
    done < "$USER_DB"
    echo -e "${YELLOW}Enter Telegram Bot Info:${NC}"
    read -p " ◇ Bot Token: " TG_TOKEN
    read -p " ◇ Chat ID: " TG_CHATID
    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then echo -e "${RED}Missing Info!${NC}"; sleep 2; return; fi
    echo -e "${YELLOW}Sending backup.txt to Telegram...${NC}"
    res=$(curl -s -F document=@"$BACKUP_FILE" "https://api.telegram.org/bot$TG_TOKEN/sendDocument?chat_id=$TG_CHATID&caption=User_Backup_File")
    if echo "$res" | grep -q '"ok":true'; then echo -e "\n${GREEN}Backup sent successfully to Telegram!${NC}"; else echo -e "\n${RED}Failed to send! Check Token/Chat ID.${NC}"; fi
    read -p " Press [Enter] to continue..."
}

user_restore() {
    clear
    echo -e "${CYAN}--- RAW LINK RESTORE (backup.txt) ---${NC}"
    read -p " ◇ Paste Raw Link: " raw_link
    if [ -z "$raw_link" ]; then return; fi
    echo -e "${YELLOW}Downloading backup.txt from link...${NC}"
    wget -q -O "$BACKUP_FILE" "$raw_link"
    if [ ! -s "$BACKUP_FILE" ]; then echo -e "${RED}Download failed or file is empty!${NC}"; sleep 2; return; fi
    echo -e "${YELLOW}Restoring users...${NC}"
    while IFS=: read -r u p exp lim; do
        [[ -z "$u" ]] && continue
        if id "$u" &>/dev/null; then echo -e "Skipped: ${YELLOW}$u${NC} (User already exists)"; continue; fi
        if [[ "$exp" == "never" || -z "$exp" ]]; then useradd -M -s /bin/false "$u" &>/dev/null; else useradd -e "$exp" -M -s /bin/false "$u" &>/dev/null; fi
        echo "$u:$p" | chpasswd &>/dev/null
        echo "$u hard maxlogins ${lim:-1}" >> /etc/security/limits.conf
        echo "$u:$p" >> "$USER_DB"
        echo -e "Restored: ${GREEN}$u${NC}"
    done < "$BACKUP_FILE"
    echo -e "\n${GREEN}Restore Completed!${NC}"; sleep 2
}

# --- PORT MANAGER LOGIC ---
get_port_v2() {
    local ports=$(netstat -tunlp | grep -i "$1" | awk '{print $4}' | awk -F: '{print $NF}' | sort -nu | xargs)
    [ -z "$ports" ] && echo -e "${RED}OFF${NC}" || echo -e "${YELLOW}$ports${NC}"
}
get_proxy_status() {
    local check=$(netstat -tunlp | grep "python3" | awk '{print $4}' | awk -F: '{print $NF}' | sort -nu | xargs)
    [ -z "$check" ] && echo -e "${RED}OFF${NC}" || echo -e "${YELLOW}$check${NC}"
}
check_st() {
    if netstat -tunlp | grep -qi "$1" > /dev/null; then echo -e "${GREEN}●${NC}"; else echo -e "${RED}○${NC}"; fi
}
setup_ws_proxy() {
    echo ""
    read -p " ဖွင့်ချင်သည့် Port ကိုရိုက်ထည့်ပါ (ဥပမာ: 80, 8080, 2052): " p_port
    [[ -z "$p_port" ]] && return
    fuser -k $p_port/tcp &> /dev/null
    cat <<EOF > /usr/local/bin/proxy_$p_port.py
import socket, threading, select
def forward(source, destination):
    string_list = [source, destination]
    while True:
        read_list, _, _ = select.select(string_list, [], [], 10)
        if not read_list: continue
        for sock in read_list:
            try:
                data = sock.recv(16384)
                if not data: return
                if sock is source: destination.sendall(data)
                else: source.sendall(data)
            except: return
def handler(client, address):
    try:
        header = client.recv(16384).decode('utf-8', errors='ignore')
        target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target.connect(('127.0.0.1', 22))
        if "Upgrade: websocket" in header or "GET" in header or "CONNECT" in header:
            client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        forward(client, target)
    except: pass
    finally: client.close()
def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', $p_port))
    server.listen(1000)
    while True:
        client, address = server.accept()
        threading.Thread(target=handler, args=(client, address), daemon=True).start()
if __name__ == '__main__': main()
EOF
    chmod +x /usr/local/bin/proxy_$p_port.py
    screen -dmS "proxy_$p_port" python3 /usr/local/bin/proxy_$p_port.py
    echo -e "${GREEN}Port $p_port အောင်မြင်စွာ ပွင့်သွားပါပြီ!${NC}"; sleep 2
}
gerenciar_proxy() {
    while true; do
        clear
        echo -e "${BLUE}╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍${NC}"
        echo -e "      ${CYAN}GERENCIAR PROXY SOCKS${NC}"
        echo -e "${BLUE}╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍${NC}"
        echo -e " ${NC}ACTIVE PORTS: $(get_proxy_status)${NC}"
        echo ""
        echo -e " ${CYAN}[1]${NC} • ABRIR PORTA (OPEN)"
        echo -e " ${CYAN}[2]${NC} • PARAR TUDO (STOP ALL)"
        echo -e " ${CYAN}[0]${NC} • VOLTAR"
        echo ""
        read -p " ESCOLHA: " opt
        case $opt in
            1) setup_ws_proxy ;;
            2) pkill -f "proxy_" && echo -e "${RED}Stopped All!${NC}" && sleep 1 ;;
            0) break ;;
        esac
    done
}
inst_ssl() {
    echo -e "${YELLOW}Configurando SSL Tunnel no porto 442...${NC}"
    apt-get install stunnel4 -y &> /dev/null
    openssl genrsa -out /etc/stunnel/stunnel.key 2048 &> /dev/null
    openssl req -new -x509 -key /etc/stunnel/stunnel.key -out /etc/stunnel/stunnel.crt -days 1095 -subj "/CN=SSHPLUS" &> /dev/null
    cat /etc/stunnel/stunnel.key /etc/stunnel/stunnel.crt > /etc/stunnel/stunnel.pem
    cat <<EOF > /etc/stunnel/stunnel.conf
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
[ssh]
accept = 442
connect = 127.0.0.1:22
EOF
    sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4
    service stunnel4 restart &> /dev/null
    systemctl restart stunnel4 &> /dev/null
    echo -e "${GREEN}SSL Tunnel Ativo!${NC}"; sleep 2
}
inst_dropbear() {
    echo -e "${YELLOW}Configurando Dropbear (143, 110)...${NC}"
    apt-get install dropbear -y &> /dev/null
    sed -i 's/NO_START=1/NO_START=0/g' /etc/default/dropbear
    sed -i 's/DROPBEAR_PORT=.*/DROPBEAR_PORT=143/g' /etc/default/dropbear
    if grep -q "DROPBEAR_EXTRA_ARGS" /etc/default/dropbear; then
        sed -i 's/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS="-p 110"/g' /etc/default/dropbear
    else
        echo 'DROPBEAR_EXTRA_ARGS="-p 110"' >> /etc/default/dropbear
    fi
    service dropbear restart &> /dev/null
    echo -e "${GREEN}Dropbear configurado!${NC}"; sleep 2
}
port_manager_menu() {
    while true; do
        clear
        local OS=$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep "PRETTY_NAME" | cut -d= -f2 | tr -d '"')
        echo -e "${NC}$OS              $(date)"
        echo -e "${BLUE}╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍${NC}"
        echo -e "              ${NC}CONEXAO${NC}"
        echo -e "${BLUE}╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍${NC}"
        echo -e "  ${CYAN}SERVICO: ${NC}OPENSSH PORTA: $(get_port_v2 sshd)"
        echo -e "  ${CYAN}SERVICO: ${NC}OPENVPN: PORTA: $(get_port_v2 openvpn)"
        echo -e "  ${CYAN}SERVICO: ${NC}PROXY SOCKS PORTA: $(get_proxy_status)"
        echo -e "  ${CYAN}SERVICO: ${NC}SSL TUNNEL PORTA: $(get_port_v2 stunnel)"
        echo -e "  ${CYAN}SERVICO: ${NC}DROPBEAR PORTA: $(get_port_v2 dropbear)"
        echo -e "  ${CYAN}SERVICO: ${NC}SQUID PORTA: $(get_port_v2 squid)"
        echo -e "${BLUE}╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍╍${NC}"
        echo ""
        echo -e " ${CYAN}[ 01 ]${NC} ${NC}⇒ OPENSSH $(check_st sshd)"
        echo -e " ${CYAN}[ 02 ]${NC} ${NC}⇒ SQUID PROXY $(check_st squid)"
        echo -e " ${CYAN}[ 03 ]${NC} ${NC}⇒ DROPBEAR $(check_st dropbear)"
        echo -e " ${CYAN}[ 04 ]${NC} ${NC}⇒ OPENVPN $(check_st openvpn)"
        echo -e " ${CYAN}[ 05 ]${NC} ${NC}⇒ PROXY SOCKS $(check_st python3)"
        echo -e " ${CYAN}[ 06 ]${NC} ${NC}⇒ SSL TUNNEL $(check_st stunnel)"
        echo -e " ${CYAN}[ 12 ]${NC} ${NC}⇒ WEBSOCKET - Corretor $(check_st python3)"
        echo -e " ${CYAN}[ 00 ]${NC} ${NC}⇒ VOLTAR ${RED}<<<${NC}"
        echo ""
        read -p "  ESCOLHA OPÇÃO DESEJADA : " port_choice
        case $port_choice in
            1|01) read -p "SSH Port: " p; sed -i "s/^Port .*/Port $p/" /etc/ssh/sshd_config; service ssh restart ;;
            2|02) apt-get install squid -y; service squid restart ;;
            3|03) inst_dropbear ;;
            4|04) wget https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh -O /tmp/ovpn.sh && chmod +x /tmp/ovpn.sh && ./tmp/ovpn.sh ;;
            5|05|12) gerenciar_proxy ;;
            6|06) inst_ssl ;;
            0|00) break ;;
            *) echo -e "${RED}Opção Inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# --- SLOWDNS MANAGER LOGIC ---
run_slowdns_manager() {
    local SCRIPT_URL="https://raw.githubusercontent.com/bugfloyd/dnstt-deploy/main/dnstt-deploy.sh"
    local SCRIPT_PATH="/usr/local/bin/dnstt-deploy"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo -e "${YELLOW}Downloading dnstt-deploy...${NC}"
        curl -Ls "$SCRIPT_URL" -o "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi
    bash "$SCRIPT_PATH"
}

# --- Main Dashboard Loop ---
while true; do
    draw_dashboard
    echo ""
    echo -e " ${YELLOW}[01]${NC} CREATE USER          ${YELLOW}[07]${NC} CHANGE DATE"
    echo -e " ${YELLOW}[02]${NC} CREATE TEST USER     ${YELLOW}[08]${NC} CHANGE LIMIT"
    echo -e " ${YELLOW}[03]${NC} REMOVE USER          ${YELLOW}[09]${NC} CHECK ALL PORTS"
    echo -e " ${YELLOW}[04]${NC} USER INFO (FULL)     ${YELLOW}[10]${NC} RESET DOMAIN/NS"
    echo -e " ${YELLOW}[05]${NC} CHANGE USERNAME      ${YELLOW}[11]${NC} ${RED}REINSTALL UBUNTU 20${NC}"
    echo -e " ${YELLOW}[06]${NC} CHANGE PASSWORD      ${YELLOW}[12]${NC} BACKUP TO TELEGRAM"
    echo -e " ${YELLOW}[13]${NC} RESTORE FROM RAW LINK ${BLUE}[14]${NC} ${BLUE}PORT MANAGER${NC}"
    echo -e " ${YELLOW}[00]${NC} EXIT                 ${BLUE}[15]${NC} ${BLUE}SLOWDNS MANAGER${NC}"
    echo ""
    read -t 60 -p " ◇ Select Option: " opt
    case $opt in
        1|01) 
            while true; do 
                clear; echo -e "${CYAN}--- CREATE NEW USER ---${NC}"; 
                read -p "Username: " user; 
                id "$user" &>/dev/null && echo -e "${RED}Already!${NC}" && sleep 1 && continue; 
                read -p "Password: " pass; 
                read -p "Days: " days; 
                read -p "Limit: " user_limit; 
                exp_date=$(date -d "+$days days" +"%Y-%m-%d" 2>/dev/null); 
                useradd -e $exp_date -M -s /bin/false $user &>/dev/null; 
                echo "$user:$pass" | chpasswd &>/dev/null; 
                sed -i "/$user hard maxlogins/d" /etc/security/limits.conf; 
                echo "$user hard maxlogins $user_limit" >> /etc/security/limits.conf; 
                echo "$user:$pass" >> "$USER_DB"; 
                show_details; 
                echo ""; 
                read -p " ◇ Return to Menu (m) or Continue (c)?: " nav; 
                [[ "$nav" != "c" ]] && break; 
            done ;;
        2|02) 
            while true; do 
                user="test_$(head /dev/urandom | tr -dc 0-9 | head -c 4)"; 
                pass="123"; user_limit="1"; 
                exp_date=$(date -d "+1 days" +"%Y-%m-%d" 2>/dev/null); 
                useradd -e $exp_date -M -s /bin/false $user &>/dev/null; 
                echo "$user:$pass" | chpasswd &>/dev/null; 
                echo "$user hard maxlogins 1" >> /etc/security/limits.conf; 
                echo "$user:$pass" >> "$USER_DB"; 
                show_details; 
                echo ""; 
                read -p " ◇ Return to Menu (m) or Continue (c)?: " nav; 
                [[ "$nav" != "c" ]] && break; 
            done ;;
        3|03) 
            while true; do 
                display_user_table; echo -e " [1] Remove Name [2] Remove ALL"; 
                read -p " Select: " rm_opt; 
                if [[ "$rm_opt" == "1" ]]; then 
                    read -p " Name: " user; 
                    userdel -f "$user" &>/dev/null && sed -i "/^$user:/d" "$USER_DB" && sed -i "/$user hard maxlogins/d" /etc/security/limits.conf && echo -e "${GREEN}Deleted!${NC}"; 
                elif [[ "$rm_opt" == "2" ]]; then 
                    read -p " Confirm Delete ALL? (y/n): " confirm; 
                    [[ "$confirm" == "y" ]] && while IFS=: read -r u p; do userdel -f "$u" &>/dev/null; sed -i "/$u hard maxlogins/d" /etc/security/limits.conf; done < "$USER_DB" && > "$USER_DB" && echo -e "${GREEN}All cleared!${NC}"; 
                fi; 
                echo ""; read -p " ◇ Return to Menu (m) or Continue (c)?: " nav; 
                [[ "$nav" != "c" ]] && break; 
            done ;;
        4|04) while true; do display_user_table; echo ""; read -p " ◇ Return to Menu (m) or Continue (c)?: " nav; [[ "$nav" != "c" ]] && break; done ;;
        5|05) 
            while true; do 
                display_user_table; read -p "Old Name: " old_u; 
                [ -z "$old_u" ] && break; 
                if ! id "$old_u" &>/dev/null; then echo -e "${RED}User not found!${NC}"; sleep 1; continue; fi; 
                read -p "New Name: " new_u; [ -z "$new_u" ] && continue; 
                if id "$new_u" &>/dev/null; then echo -e "${RED}New name already exists!${NC}"; sleep 1; continue; fi; 
                pkill -u "$old_u" &>/dev/null; sleep 0.5; 
                usermod -l "$new_u" "$old_u" &>/dev/null && groupmod -n "$new_u" "$old_u" &>/dev/null; 
                sed -i "s/^$old_u:/$new_u:/" "$USER_DB"; 
                sed -i "s/$old_u hard/$new_u hard/" /etc/security/limits.conf; 
                echo -e "${GREEN}Username changed successfully!${NC}"; 
                echo ""; read -p " ◇ Return to Menu (m) or Continue (c)?: " nav; [[ "$nav" != "c" ]] && break; 
            done ;;
        6|06) 
            while true; do 
                display_user_table; read -p "User: " user; read -p "New Pass: " pass; 
                echo "$user:$pass" | chpasswd &>/dev/null && sed -i "s/^$user:.*/$user:$pass/" "$USER_DB"; 
                echo ""; read -p " ◇ Return to Menu (m) or Continue (c)?: " nav; [[ "$nav" != "c" ]] && break; 
            done ;;
        7|07) 
            while true; do 
                display_user_table; read -p "User: " user; read -p "Date (YYYY-MM-DD): " exp_date; 
                usermod -e $exp_date $user &>/dev/null; 
                echo ""; read -p " ◇ Return to Menu (m) or Continue (c)?: " nav; [[ "$nav" != "c" ]] && break; 
            done ;;
        8|08) 
            while true; do 
                display_user_table; read -p "User: " user; read -p "Limit: " user_limit; 
                sed -i "/$user hard maxlogins/d" /etc/security/limits.conf; 
                echo "$user hard maxlogins $user_limit" >> /etc/security/limits.conf; 
                echo ""; read -p " ◇ Return to Menu (m) or Continue (c)?: " nav; [[ "$nav" != "c" ]] && break; 
            done ;;
        9|09) 
            while true; do 
                clear; get_ports; echo -e "${CYAN}Current Ports:${NC}"; 
                echo "SSH: $SSH_PORT"; echo "WS: $WS_PORT"; echo "Squid: $SQUID_PORT"; 
                echo "Dropbear: $DROPBEAR_PORT"; echo "Stunnel: $STUNNEL_PORT"; 
                echo ""; read -p " ◇ Return to Menu (m) or Continue (c)?: " nav; [[ "$nav" != "c" ]] && break; 
            done ;;
        10) rm -f "$CONFIG_FILE"; do_initial_setup ;;
        11) clear; read -p "New Root Pass: " re_pass; read -p "Confirm (y/n): " confirm; [[ "$confirm" == "y" ]] && apt update -y && apt install gawk tar wget curl -y && wget -qO reinstall.sh https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh && bash reinstall.sh ubuntu 20.04 --password "$re_pass" && reboot ;;
        12) user_backup ;;
        13) user_restore ;;
        14) port_manager_menu ;;
        15) run_slowdns_manager ;;
        0|00) exit 0 ;;
        *) sleep 1 ;;
    esac
done
