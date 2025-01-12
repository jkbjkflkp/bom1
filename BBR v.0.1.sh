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

# Функции для работы с BBR и настройками сети
function check_bbr_status {
    if grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control; then
        BBR_STATUS=$(/sbin/sysctl -n net.ipv4.tcp_congestion_control)
        if [[ "$BBR_STATUS" == *"bbr"* ]]; then
            log_action "BBR is enabled."
            echo "BBR включен."
        else
            log_action "BBR is disabled, enabling is recommended."
            echo "BBR выключен. Рекомендуется включить BBR для улучшения производительности сети."
        fi
    else
        log_action "BBR is not supported by your kernel."
        echo "BBR не поддерживается вашим ядром."
    fi
}

function create_backup {
    BACKUP_DIR="/etc/backup_network_settings_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    /bin/cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.bak"
    /bin/cp /etc/security/limits.conf "$BACKUP_DIR/limits.conf.bak"
    if [ $? -eq 0 ]; then
        log_action "Backup created in $BACKUP_DIR"
        echo "Резервные копии созданы в $BACKUP_DIR"
    else
        log_action "Failed to create backup."
        echo "Ошибка создания резервных копий."
        return 1
    fi
}

function apply_short_connections_settings {
    log_action "Applying settings for short connections..."
    /sbin/sysctl -w net.ipv4.tcp_syncookies=1
    /sbin/sysctl -w net.ipv4.tcp_synack_retries=2
    /sbin/sysctl -w net.ipv4.tcp_syn_retries=3
    echo "Настройки для коротких соединений применены."
}

function apply_long_connections_settings {
    log_action "Applying settings for long connections..."
    /sbin/sysctl -w net.core.rmem_max=134217728
    /sbin/sysctl -w net.core.wmem_max=134217728
    /sbin/sysctl -w net.ipv4.tcp_keepalive_time=1800
    echo "Настройки для длительных соединений применены."
}

function restore_bbr {
    log_action "Restoring BBR to default settings..."
    /sbin/sysctl -w net.ipv4.tcp_congestion_control=cubic
    echo "Настройки BBR восстановлены."
}

function restore_defaults {
    log_action "Restoring all settings to defaults..."
    /sbin/sysctl -p /etc/sysctl.conf.bak
    echo "Все настройки были возвращены к дефолтным значениям."
}

function remove_bbr {
    log_action "Removing BBR from system..."
    /sbin/sysctl -w net.ipv4.tcp_congestion_control=cubic
    echo "BBR удален, возвращено использование стандартного алгоритма."
}

# Главное меню и подменю функций
function main_menu {
    while true; do
        echo "Главное меню:"
        echo "1) Установить BBR"
        echo "2) Активировать BBR в качестве алгоритма управления перегрузками по умолчанию"
        echo "3) Настройка BBR с выбором типа нагрузки для VLESS"
        echo "4) Сервис и Восстановление"
        echo "5) Выход"
        read -p "Введите номер действия (1/2/3/4/5): " action_choice

        case $action_choice in
            1) install_bbr ;;
            2) activate_bbr ;;
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
