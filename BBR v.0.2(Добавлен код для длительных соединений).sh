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

# Функция для создания или обновления резервной копии
function backup_file {
    local file="$1"
    local backup_dir="/var/backups"
    local backup_file="$backup_dir/$(basename $file).bak"

    mkdir -p "$backup_dir"

    if [ -e "$file" ]; then
        if [ ! -e "$backup_file" ]; then
            cp "$file" "$backup_file"
            log_action "Создана резервная копия $file -> $backup_file"
        else
            if ! cmp -s "$file" "$backup_file"; then
                cp "$file" "$backup_file.$(date +%Y%m%d%H%M%S)"
                cp "$file" "$backup_file"
                log_action "Обновлена резервная копия $file -> $backup_file"
            fi
        fi
    fi
}

# Функция для восстановления из резервной копии
function restore_backup {
    local file="$1"
    local backup_dir="/var/backups"
    local backup_file="$backup_dir/$(basename $file).bak"

    if [ -e "$backup_file" ]; then
        cp "$backup_file" "$file"
        log_action "Восстановлен файл $file из резервной копии $backup_file"
        echo "Файл $file успешно восстановлен из резервной копии."
    else
        echo "Резервная копия для файла $file не найдена."
    fi
}

# Функции для включения и выключения BBR
function enable_bbr {
    log_action "Attempting to enable BBR..."
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "\033[0;33mBBR is already enabled.\033[0m"
    else
        backup_file /etc/sysctl.conf
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
        backup_file /etc/sysctl.conf
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

# Функция для настройки длительных соединений
function configure_long_connections {
    log_action "Configuring long connections optimization..."

    local log_file="/var/log/tcp_udp_optimization.log"
    echo "Начало работы скрипта $(date)" | sudo tee -a "$log_file"

    echo "Скрипт для оптимизации TCP (+BBR) и UDP на Linux сервере" | sudo tee -a "$log_file"

    function remove_existing_settings() {
        local file="$1"
        shift
        backup_file "$file"
        for setting in "$@"; do
            sudo sed -i "/^$setting/d" "$file"
            if [[ $? -ne 0 ]]; then
                echo "Ошибка при удалении настроек из $file" | sudo tee -a "$log_file"
                exit 1
            fi
        done
    }

    function add_or_update_setting() {
        local file="$1"
        local setting="$2"
        local key="${setting%%=*}"
        local value="${setting#*=}"

        backup_file "$file"

        if grep -qE "^$key\\s*=" "$file"; then
            sudo sed -i "s/^$key\\s*=.*/$setting/" "$file"
            if [[ $? -ne 0 ]]; then
                echo "Ошибка при обновлении $key в $file" | sudo tee -a "$log_file"
                exit 1
            fi
            echo "Обновлено: $key" | sudo tee -a "$log_file"
        else
            echo "$setting" | sudo tee -a "$file" > /dev/null
            if [[ $? -ne 0 ]]; then
                echo "Ошибка при добавлении $setting в $file" | sudo tee -a "$log_file"
                exit 1
            fi
            echo "Добавлено: $setting" | sudo tee -a "$log_file"
        fi
    }

    echo "Обновление /etc/security/limits.conf..." | sudo tee -a "$log_file"
    remove_existing_settings /etc/security/limits.conf "* soft nofile" "* hard nofile" "root soft nofile" "root hard nofile"

    add_or_update_setting /etc/security/limits.conf "* soft nofile 51200"
    add_or_update_setting /etc/security/limits.conf "* hard nofile 51200"
    add_or_update_setting /etc/security/limits.conf "root soft nofile 51200"
    add_or_update_setting /etc/security/limits.conf "root hard nofile 51200"

    echo "Добавление настроек TCP и UDP в /etc/sysctl.conf..." | sudo tee -a "$log_file"
    settings=(
        "fs.file-max = 51200"
        "net.core.rmem_max = 67108864"
        "net.core.wmem_max = 67108864"
        "net.core.netdev_max_backlog = 10000"
        "net.core.somaxconn = 4096"
        "net.core.default_qdisc = fq"
        "net.ipv4.tcp_syncookies = 1"
        "net.ipv4.tcp_tw_reuse = 1"
        "net.ipv4.tcp_fin_timeout = 10"
        "net.ipv4.tcp_keepalive_time = 1800"
        "net.ipv4.tcp_keepalive_probes = 5"
        "net.ipv4.tcp_keepalive_intvl = 30"
        "net.ipv4.tcp_max_syn_backlog = 8192"
        "net.ipv4.ip_local_port_range = 10000 65000"
        "net.ipv4.tcp_slow_start_after_idle = 0"
        "net.ipv4.tcp_max_tw_buckets = 5000"
        "net.ipv4.tcp_fastopen = 3"
        "net.ipv4.tcp_no_metrics_save = 1"
        "net.ipv4.tcp_max_orphans = 32768"
        "net.ipv4.udp_mem = 25600 51200 102400"
        "net.ipv4.tcp_mem = 25600 51200 102400"
        "net.ipv4.tcp_rmem = 4096 87380 67108864"
        "net.ipv4.tcp_wmem = 4096 65536 67108864"
        "net.ipv4.tcp_mtu_probing = 1"
        "net.ipv4.tcp_congestion_control = bbr"
        "net.ipv4.udp_rmem_min = 16384"
        "net.ipv4.udp_wmem_min = 16384"
        "net.ipv4.tcp_syn_retries = 3"
        "net.ipv4.tcp_synack_retries = 3"
    )

    for setting in "${settings[@]}"; do
        add_or_update_setting /etc/sysctl.conf "$setting"
    done

    echo "Применение изменений..." | sudo tee -a "$log_file"
    if ! sudo sysctl -p; then
        echo "Не удалось применить настройки sysctl." | sudo tee -a "$log_file"
        exit 1
    fi

    echo "Изменения успешно применены. Сервер будет перезагружен через 5 секунд..." | sudo tee -a "$log_file"
    echo "Сервер будет перезагружен для применения изменений. Продолжить? (yes/no)"
    read response
    if [[ "$response" == "yes" ]]; then
        sudo reboot
    else
        echo "Перезагрузка отменена." | sudo tee -a "$log_file"
        exit 0
    fi
}

# Подменю для настройки типа нагрузки
function load_type_menu {
    while true; do
        echo "Выберите тип нагрузки сети сервера:"
        echo "1) Короткие соединения (например, веб-серфинг, API)"
        echo "2) Длительные соединения (например, потоковая передача: YouTube, Discord)"
        echo "3) Стандартные настройки (Стандартные настройки BBR)"
        echo "4) Выйти в главное меню"
        read -p "Введите номер (1, 2, 3, или 4): " type_choice

        case $type_choice in
            1) echo "Применение настроек для коротких соединений...";;
            2) configure_long_connections ;;
            3) 
                echo "Восстановление стандартных настроек BBR..."
                restore_backup /etc/sysctl.conf
                restore_backup /etc/security/limits.conf
                echo "Применение стандартных настроек..."
                sudo sysctl -p
                echo "Сервер будет перезагружен для применения изменений. Продолжить? (yes/no)"
                read response
                if [[ "$response" == "yes" ]]; then
                    sudo reboot
                else
                    echo "Перезагрузка отменена."
                fi
                ;;
            4) return ;;
            *) echo "Неверный выбор. Попробуйте снова."
               continue ;;
        esac
    done
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
