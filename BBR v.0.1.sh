#!/bin/bash

# Проверка прав администратора
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Скрипт должен быть запущен с правами root."
    exit 1
fi

# Создание и настройка файла логирования
LOG_FILE="/var/log/network_script.log"
touch $LOG_FILE
chmod 600 $LOG_FILE

# Функция для логирования действий
function log_action {
    echo "$(date +"%Y-%m-%d %T"): $1" >> $LOG_FILE
}

# Функции для включения и выключения BBR
function enable_bbr {
    log_action "Attempting to enable BBR..."
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "\033[0;33mBBR is already enabled.\033[0m"
    else
        echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
        echo -e "\033[0;32mBBR has been enabled.\033[0m"
        log_action "BBR enabled successfully."
    fi
    echo "Если у вас есть следующий вывод 'net.ipv4.tcp_congestion_control = bbr', вы успешно включили алгоритм BBR Google."
    read -p "Нажмите Enter, чтобы вернуться в главное меню..."
}

function disable_bbr {
    log_action "Attempting to disable BBR..."
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        sudo sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf
        sudo sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=cubic" | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
        echo -e "\033[0;32mBBR has been disabled and CUBIC has been enabled.\033[0m"
        log_action "BBR disabled successfully."
    else
        echo -e "\033[0;33mBBR is not enabled. No changes needed.\033[0m"
    fi
    read -p "Нажмите Enter, чтобы вернуться в главное меню..."
}

# Функция для отображения статуса BBR
function show_bbr_status {
    echo "$(sysctl net.ipv4.tcp_congestion_control)"
    read -p "Нажмите Enter, чтобы вернуться в главное меню..."
}

# Главное меню и подменю функций
function main_menu {
    while true; do
        echo "Главное меню:"
        echo "1) Включить BBR"
        echo "2) Выключить BBR"
        echo "3) Статус BBR"
        echo "4) Настройка BBR с выбором типа нагрузки сети"
        echo "5) Выход"
        read -p "Введите номер действия (1/2/3/4/5): " action_choice

        case $action_choice in
            1) enable_bbr ;;
            2) disable_bbr ;;
            3) show_bbr_status ;;
            4) load_type_menu ;;
            5) break ;;
            *) echo "Неверный выбор. Попробуйте снова."
               continue ;;
        esac
    done
}

# Запуск главного меню при старте скрипта
main_menu
