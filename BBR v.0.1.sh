#!/bin/bash

# Проверка прав администратора
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Скрипт должен быть запущен с правами root."
    exit 1
fi

# Логирование действий скрипта
LOG_FILE="/var/log/network_script.log"
touch $LOG_FILE
chmod 600 $LOG_FILE

# Функция для логирования действий
function log_action {
    echo "$(date +"%Y-%m-%d %T"): $1" >> $LOG_FILE
}

# ANSI escape codes for colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# check if BBR is enabled
function check_bbr_enabled {
    /sbin/sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"
    return $?
}

# enable BBR
function enable_bbr {
    echo -e "${CYAN}Enabling BBR...${NC}"
    echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    sudo /sbin/sysctl -p
    echo -e "${GREEN}BBR has been enabled.${NC}"
}

# disable BBR and enable CUBIC
function disable_bbr_enable_cubic {
    echo -e "${CYAN}Disabling BBR and enabling CUBIC...${NC}"
    
    # Remove BBR settings from sysctl.conf
    sudo sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf
    sudo sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf
    
    # Set CUBIC as the default congestion control algorithm
    echo "net.ipv4.tcp_congestion_control=cubic" | sudo tee -a /etc/sysctl.conf
    
    # Apply the changes
    sudo /sbin/sysctl -p
    
    echo -e "${GREEN}BBR has been disabled and CUBIC has been enabled.${NC}"
}

# Главное меню и подменю функций
function main_menu {
    while true; do
        echo "Главное меню:"
        echo "1) Включить BBR"
        echo "2) Выключить BBR"
        echo "3) Настройка BBR с выбором типа нагрузки для VLESS"
        echo "4) Сервис и Восстановление"
        echo "5) Выход"
        read -p "Введите номер действия (1/2/3/4/5): " action_choice

        case $action_choice in
            1) 
                if check_bbr_enabled; then
                    echo -e "${ORANGE}BBR is already enabled.${NC}"
                else
                    enable_bbr
                fi ;;
            2) 
                if check_bbr_enabled; then
                    disable_bbr_enable_cubic
                else
                    echo -e "${ORANGE}BBR is not enabled. No changes needed.${NC}"
                fi ;;
            3) load_type_menu ;;
            4) service_and_restore_menu ;;
            5) break ;;
            *) echo "Неверный выбор. Попробуйте снова."
               continue ;;
        esac
    done
}

function load_type_menu {
    while true; do
        echo "Выберите тип нагрузки для VLESS:"
        echo "1) Короткие соединения (например, веб-серфинг, API)"
        echo "2) Длительные соединения (например, потоковая передача: YouTube, Discord, VoIP)"
        echo "3) Вернуться в главное меню"
        read -p "Введите номер (1, 2 или 3): " load_type

        case $load_type in
            1) apply_short_connections_settings ;;
            2) apply_long_connections_settings ;;
            3) return ;;
            *) echo "Неверный выбор. Попробуйте снова."
               continue ;;
        esac
    done
}

function service_and_restore_menu {
    while true; do
        echo "1) Восстановить BBR к дефолтным настройкам"
        echo "2) Полный откат настроек к дефолтным значениям"
        echo "3) Удалить BBR из системы"
        echo "4) Вернуться в главное меню"
        read -p "Введите номер действия (1/2/3/4): " service_choice

        case $service_choice in
            1) restore_bbr ;;
            2) restore_defaults ;;
            3) remove_bbr ;;
            4) return ;;
            *) echo "Неверный выбор. Попробуйте снова."
               continue ;;
        esac
    done
}

# Запуск главного меню при старте скрипта
main_menu
