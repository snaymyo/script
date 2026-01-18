#!/bin/bash

if ! command -v netstat &> /dev/null; then
    apt update -y &> /dev/null
    apt install net-tools lsb-release -y &> /dev/null
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BLUE='\033[1;34m'
NC='\033[0m'

CONFIG_FILE="/etc/evt_config"
USER_DB="/etc/evt_users.db"
[ ! -f "$USER_DB" ] && touch "$USER_DB"

do_initial_setup() {
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
    source "$CONFIG_FILE"
}

[ ! -f "$CONFIG_FILE" ] && do_initial_setup
source "$CONFIG_FILE"

check_port() {
    local service=$1
    local result=$(netstat -tunlp | grep LISTEN | grep -i "$service" | awk '{print $4}' | sed 's/.*://' | sort -u | xargs)
    [ -z "$result" ] && echo "None" || echo "$result"
}

get_ports() {
    SSH_PORT=$(check_port "sshd")
    WS_PORT=$(netstat -tunlp | grep LISTEN | grep -E 'python|node|ws-st|proxy|litespeed|go-ws' | awk '{print $4}' | sed 's/.*://' | sort -u | xargs); [ -z "$WS_PORT" ] && WS_PORT="None"
    SQUID_PORT=$(check_port "squid")
    DROPBEAR_PORT=$(check_port "dropbear")
    STUNNEL_PORT=$(netstat -tunlp | grep LISTEN | grep -E 'stunnel|stunnel4' | awk '{print $4}' | sed 's/.*://' | sort -u | xargs); [ -z "$STUNNEL_PORT" ] && STUNNEL_PORT="None"
    OHP_PORT=$(check_port "ohp")
    OVPN_TCP=$(netstat -tunlp | grep LISTEN | grep openvpn | grep tcp | awk '{print $4}' | sed 's/.*://' | sort -u | xargs); [ -z "$OVPN_TCP" ] && OVPN_TCP="None"
    OVPN_UDP=$(netstat -tunlp | grep udp | grep openvpn | awk '{print $4}' | sed 's/.*://' | sort -u | xargs); [ -z "$OVPN_UDP" ] && OVPN_UDP="None"
    OVPN_SSL="$STUNNEL_PORT"
}

get_slowdns_key() {
    if [ -f "/etc/dnstt/server.pub" ]; then
        DNS_PUB_KEY=$(cat "/etc/dnstt/server.pub" | tr -d '\n\r ')
    else
        DNS_PUB_KEY=$(find /etc/dnstt -name "*.pub" 2>/dev/null | xargs cat 2>/dev/null | head -n 1 | tr -d '\n\r ')
    fi
    [ -z "$DNS_PUB_KEY" ] && DNS_PUB_KEY="None"
}

show_details() {
    clear
    get_slowdns_key
    get_ports
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${YELLOW}           -- SSH & VPN ACCOUNT DETAILS --${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    printf " %-16s : ${GREEN}%s${NC}\n" "Username" "$user"
    printf " %-16s : ${GREEN}%s${NC}\n" "Password" "$pass"
    printf " %-16s : ${GREEN}%s${NC}\n" "Expired Date" "$exp_date"
    printf " %-16s : ${GREEN}%s Device(s)${NC}\n" "Limit" "$user_limit"
    printf " %-16s : ${YELLOW}%s${NC}\n" "Domain" "$DOMAIN"
    printf " %-16s : ${YELLOW}%s${NC}\n" "NS Domain" "$NS_DOMAIN"
    printf " %-16s : ${CYAN}%s${NC}\n" "Publickey" "$DNS_PUB_KEY"
    echo -e " "
    printf " %-16s : ${WHITE}%s${NC}\n" "SSH Port" "$SSH_PORT"
    printf " %-16s : ${WHITE}%s${NC}\n" "SSH Websocket" "$WS_PORT"
    printf " %-16s : ${WHITE}%s${NC}\n" "Squid Port" "$SQUID_PORT"
    printf " %-16s : ${WHITE}%s${NC}\n" "Dropbear Port" "$DROPBEAR_PORT"
    printf " %-16s : ${WHITE}%s${NC}\n" "Stunnel Port" "$STUNNEL_PORT"
    printf " %-16s : ${WHITE}%s${NC}\n" "OHP Port" "$OHP_PORT"
    printf " %-16s : ${WHITE}%s${NC}\n" "OVPN TCP" "$OVPN_TCP"
    printf " %-16s : ${WHITE}%s${NC}\n" "OVPN UDP" "$OVPN_UDP"
    printf " %-16s : ${WHITE}%s${NC}\n" "OVPN SSL" "$OVPN_SSL"
    echo -e "${CYAN}=====================================================${NC}"
}

get_system_info() {
    OS_NAME=$(lsb_release -ds 2>/dev/null | cut -c 1-20); [ -z "$OS_NAME" ] && OS_NAME="Ubuntu 20.04"
    UPTIME_VAL=$(uptime -p | sed 's/up //; s/ hours\?,/h/; s/ minutes\?/m/; s/ days\?,/d/' | cut -c 1-12)
    RAM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
    RAM_USED_PERC=$(free | grep Mem | awk '{printf("%.2f%%", $3/$2*100)}')
    CPU_CORES=$(nproc); CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{printf("%.2f%%", $2 + $4)}')
    
    TOTAL_USERS=$(wc -l < "$USER_DB")
    ONLINE_USERS=$(netstat -tnp 2>/dev/null | grep sshd | grep ESTABLISHED | wc -l)
    
    EXPIRED_USERS=0; CURRENT_SEC=$(date +%s)
    while IFS=: read -r u p; do
        EXP_R=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2)
        if [[ -n "$EXP_R" && "$EXP_R" != " never" ]]; then
            EXP_S=$(date -d "$EXP_R" +%s 2>/dev/null); [[ $EXP_S -le $CURRENT_SEC ]] && ((EXPIRED_USERS++))
        fi
    done < "$USER_DB"
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
    printf " ${CYAN}│${NC}  ${GREEN}◇  Online:${NC} %-12s  ${RED}◇  expired:${NC} %-13s  ${YELLOW}◇  Total:${NC} %-21s ${CYAN}│${NC}\n" "$ONLINE_USERS" "$EXPIRED_USERS" "$TOTAL_USERS"
    echo -e " ${CYAN}└──────────────────────────────────────────────────────────────────────────┘${NC}"
}

display_user_table() {
    clear
    echo -e "${CYAN}=========================================================================${NC}"
    printf "${YELLOW} %-15s | %-12s | %-10s | %-15s${NC}\n" "Username" "Password" "Status" "Expiry Date"
    echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
    if [ ! -s "$USER_DB" ]; then
        echo -e "               ${RED}No created users found.${NC}"
    else
        while IFS=: read -r username pass_find; do
            if id "$username" &>/dev/null; then
                exp_t=$(chage -l "$username" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
                [ -z "$exp_t" ] || [[ "$exp_t" == "never" ]] && exp_t="No Expiry"
                is_on=$(netstat -tnp 2>/dev/null | grep sshd | grep ESTABLISHED | grep -w "$username")
                [ -z "$is_on" ] && stat_print="${RED}Offline${NC}" || stat_print="${GREEN}Online${NC}"
                printf " %-15s | %-12s | %-19b | %-15s\n" "$username" "$pass_find" "$stat_print" "$exp_t"
            fi
        done < "$USER_DB"
    fi
    echo -e "${CYAN}=========================================================================${NC}"
}

while true; do
    draw_dashboard
    echo ""
    echo -e " ${YELLOW}[01]${NC} CREATE USER          ${YELLOW}[07]${NC} CHANGE DATE"
    echo -e " ${YELLOW}[02]${NC} CREATE TEST USER     ${YELLOW}[08]${NC} CHANGE LIMIT"
    echo -e " ${YELLOW}[03]${NC} REMOVE USER          ${YELLOW}[09]${NC} CHECK ALL PORTS"
    echo -e " ${YELLOW}[04]${NC} USER INFO (FULL)     ${YELLOW}[10]${NC} RESET DOMAIN/NS"
    echo -e " ${YELLOW}[05]${NC} CHANGE USERNAME      ${YELLOW}[11]${NC} ${RED}REINSTALL UBUNTU 20${NC}"
    echo -e " ${YELLOW}[06]${NC} CHANGE PASSWORD      ${YELLOW}[00]${NC} EXIT"
    echo ""
    read -p " ◇ Select Option: " opt
    case $opt in
        1|01) clear; echo -e "${CYAN}--- CREATE NEW USER ---${NC}"; read -p "Username: " user; id "$user" &>/dev/null && echo -e "${RED}Already Username!${NC}" && sleep 2 && continue
            read -p "Password: " pass; read -p "Days: " days; read -p "Limit: " user_limit
            exp_date=$(date -d "+$days days" +"%Y-%m-%d"); useradd -e $exp_date -M -s /bin/false $user
            echo "$user:$pass" | chpasswd
            sed -i "/$user hard maxlogins/d" /etc/security/limits.conf
            echo "$user hard maxlogins $user_limit" >> /etc/security/limits.conf
            echo "$user:$pass" >> "$USER_DB"; show_details; read -p "Enter to menu..." nav ;;
        2|02) user="test_$(head /dev/urandom | tr -dc 0-9 | head -c 4)"; pass="123"; user_limit="1"; exp_date=$(date -d "+1 days" +"%Y-%m-%d")
            useradd -e $exp_date -M -s /bin/false $user; echo "$user:$pass" | chpasswd; echo "$user:$pass" >> "$USER_DB"; show_details; read -p "Enter to menu..." nav ;;
        3|03) display_user_table; echo -e " [1] Remove Name [2] Remove ALL"; read -p " Select: " rm_opt
            if [[ "$rm_opt" == "1" ]]; then 
                read -p " Name: " user
                userdel -f "$user" && sed -i "/^$user:/d" "$USER_DB" && sed -i "/$user hard maxlogins/d" /etc/security/limits.conf && echo -e "${GREEN}Deleted!${NC}"
            elif [[ "$rm_opt" == "2" ]]; then 
                read -p " Confirm Delete ALL Created Users? (y/n): " confirm
                if [[ "$confirm" == "y" ]]; then
                    while IFS=: read -r u p; do
                        userdel -f "$u" &>/dev/null
                        sed -i "/$u hard maxlogins/d" /etc/security/limits.conf
                    done < "$USER_DB"
                    > "$USER_DB"
                    echo -e "${GREEN}All created users cleared!${NC}"
                fi
            fi; sleep 2 ;;
        4|04) display_user_table; read -p "Enter to menu..." nav ;;
        5|05) display_user_table; read -p "Old: " old_u; read -p "New: " new_u; usermod -l $new_u $old_u && sed -i "s/^$old_u:/$new_u:/" "$USER_DB" && sed -i "s/$old_u hard/$new_u hard/" /etc/security/limits.conf ;;
        6|06) display_user_table; read -p "User: " user; read -p "Pass: " pass; echo "$user:$pass" | chpasswd && sed -i "s/^$user:.*/$user:$pass/" "$USER_DB";;
        7|07) display_user_table; read -p "User: " user; read -p "Date (YYYY-MM-DD): " exp_date; usermod -e $exp_date $user ;;
        8|08) display_user_table; read -p "User: " user; read -p "Limit: " user_limit; sed -i "/$user hard maxlogins/d" /etc/security/limits.conf; echo "$user hard maxlogins $user_limit" >> /etc/security/limits.conf ;;
        9|09) clear; get_ports; echo -e "${CYAN}Current Ports:${NC}"; echo "SSH: $SSH_PORT"; echo "WS: $WS_PORT"; echo "Squid: $SQUID_PORT"; echo "Dropbear: $DROPBEAR_PORT"; echo "Stunnel: $STUNNEL_PORT"; read -p "Enter to menu..." nav ;;
        10) rm -f "$CONFIG_FILE"; do_initial_setup ;;
        11) clear; read -p "New Root Pass: " re_pass; read -p "Confirm (y/n): " confirm; 
            if [[ "$confirm" == "y" ]]; then 
                apt update -y && apt install gawk tar wget curl -y 
                wget -qO reinstall.sh https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh 
                bash reinstall.sh ubuntu 20.04 --password "$re_pass" 
                reboot 
            fi ;;
        0|00) exit 0 ;;
        *) sleep 1 ;;
    esac
done
