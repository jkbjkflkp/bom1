#!/bin/bash

# --------------------------------------------------
#          ГЛОБАЛЬНЫЕ НАСТРОЙКИ
# --------------------------------------------------

LOG_FILE="/var/log/network_script.log"
BACKUP_DIR="/var/backups"
mkdir -p "$BACKUP_DIR"

# Проверка прав администратора
if [[ $EUID -ne 0 ]]; then
    echo "Ошибка: Скрипт должен быть запущен с правами root (sudo)."
    exit 1
fi

# Создаём/настраиваем общий лог-файл
touch "$LOG_FILE" && chmod 600 "$LOG_FILE"

# Функция для логирования действий
log_action() {
    echo "$(date +"%Y-%m-%d %T"): $1" >> "$LOG_FILE"
}

# --------------------------------------------------
#    (П.4) ФУНКЦИЯ ДЛЯ БЕЗОПАСНОГО УДАЛЕНИЯ ЧЕРЕЗ sed
# --------------------------------------------------
# Позволяет проверить, действительно ли были удалены строки.
safe_sed_remove() {
    local pattern="$1"
    local file="$2"

    if [[ ! -f "$file" ]]; then
        echo "Файл $file не существует, пропускаем удаление \"$pattern\"."
        log_action "safe_sed_remove: файл $file не найден, пропущено \"$pattern\"."
        return 0
    fi

    # Считаем, сколько строк потенциально могут совпадать
    local lines_before
    lines_before=$(grep -cE "$pattern" "$file")

    sed -i "/$pattern/d" "$file"
    local ret=$?

    if [[ $ret -ne 0 ]]; then
        echo "Ошибка sed при удалении \"$pattern\" в $file (код возврата $ret)."
        log_action "safe_sed_remove: ошибка sed при удалении \"$pattern\" в $file."
        return $ret
    fi

    # Проверяем, действительно ли что-то удалилось
    local lines_after
    lines_after=$(grep -cE "$pattern" "$file")

    if [[ "$lines_before" -eq 0 ]]; then
        log_action "safe_sed_remove: Строки \"$pattern\" не найдены в $file, нечего удалять."
    else
        local diff=$(( lines_before - lines_after ))
        log_action "safe_sed_remove: Удалено $diff вхождений \"$pattern\" из $file."
    fi

    return 0
}

# Функция для создания или обновления резервной копии
backup_file() {
    local file="$1"
    local backup_file="$BACKUP_DIR/$(basename "$file").bak"

    if [[ -e "$file" ]]; then
        # Если нет .bak — создаём
        if [[ ! -e "$backup_file" ]]; then
            cp "$file" "$backup_file"
            log_action "Создана резервная копия $file -> $backup_file"
        else
            # Если файл поменялся — делаем дополнительную копию с датой
            if ! cmp -s "$file" "$backup_file"; then
                local dated_backup="$backup_file.$(date +%Y%m%d%H%M%S)"
                cp "$file" "$dated_backup"
                cp "$file" "$backup_file"
                log_action "Обновлена резервная копия $file -> $backup_file (и $dated_backup)"
            fi
        fi
    fi
}

# --------------------------------------------------
# (П.5) ФУНКЦИЯ ДЛЯ ВОССТАНОВЛЕНИЯ ИЗ РЕЗЕРВНОЙ КОПИИ
#    + ОБРАБОТКА СЛУЧАЯ, КОГДА БЭКАП ОТСУТСТВУЕТ
# --------------------------------------------------
restore_backup() {
    local file="$1"
    local backup_file="$BACKUP_DIR/$(basename "$file").bak"

    if [[ -e "$backup_file" ]]; then
        cp "$backup_file" "$file"
        log_action "Восстановлен файл $file из резервной копии $backup_file"
        echo "Файл $file успешно восстановлен из резервной копии."
    else
        echo "Внимание: резервная копия для файла $file не найдена. Настройки не будут изменены."
        log_action "restore_backup: бэкап для $file отсутствует, пропущено восстановление."
    fi
}

# Функция для предложения перезагрузки
ask_for_reboot() {
    echo "Перезагрузка необходима для полного применения настроек. Перезагрузить сейчас? (yes/no)"
    read -r response
    if [[ "$response" == "yes" ]]; then
        echo "Система будет перезагружена..."
        log_action "Инициирована перезагрузка системы пользователем."
        reboot
    else
        echo "Перезагрузка отменена пользователем."
        log_action "Пользователь отказался от перезагрузки."
    fi
}

# --------------------------------------------------
# (П.6) ПРОВЕРКА КОНФЛИКТОВ В /etc/sysctl.d
# --------------------------------------------------
# Некоторые параметры (например, net.core.default_qdisc, net.ipv4.tcp_congestion_control)
# могут быть переопределены файлами в /etc/sysctl.d/*.conf.
# Если найдём строчку вида 'net.ipv4.tcp_congestion_control' в этих конфиг-файлах — предупредим.
check_sysctl_d_conflicts() {
    local param="$1"
    local sysctl_d_dir="/etc/sysctl.d"
    if [[ ! -d "$sysctl_d_dir" ]]; then
        # Нет каталога sysctl.d (старые системы) — ничего не делаем
        return 0
    fi

    local file
    for file in "$sysctl_d_dir"/*.conf; do
        # Пропускаем, если файла нет (глоб не нашёл)
        [[ ! -f "$file" ]] && continue

        if grep -Eq "^[[:space:]]*$param" "$file"; then
            echo "Внимание: параметр '$param' уже задан в $file — возможен конфликт."
            log_action "check_sysctl_d_conflicts: $param найден в $file (возможен конфликт)."
        fi
    done
}

# --------------------------------------------------
#       УПРАВЛЕНИЕ BBR
# --------------------------------------------------

enable_bbr() {
    log_action "Attempting to enable BBR..."
    local current_qdisc
    local current_congestion

    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    current_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)

    echo -e "Текущие параметры:"
    echo -e "  net.core.default_qdisc = ${current_qdisc:-<не задан>}"
    echo -e "  net.ipv4.tcp_congestion_control = ${current_congestion:-<не задан>}"

    if [[ "$current_congestion" == "bbr" ]]; then
        echo -e "\033[0;33mBBR уже включён.\033[0m"
        return
    fi

    # Проверяем наличие поддержки BBR
    if ! modinfo tcp_bbr &>/dev/null; then
        echo -e "\033[0;31mОшибка: Ваше ядро не поддерживает BBR.\033[0m"
        log_action "Failed to enable BBR: Kernel does not support BBR."
        return 1
    fi

    backup_file /etc/sysctl.conf

    # Удаляем старые параметры, если они есть
    safe_sed_remove "net.core.default_qdisc" /etc/sysctl.conf
    safe_sed_remove "net.ipv4.tcp_congestion_control" /etc/sysctl.conf

    # Добавляем новые параметры
    {
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_congestion_control=bbr"
    } >> /etc/sysctl.conf

    check_sysctl_d_conflicts "net.core.default_qdisc"
    check_sysctl_d_conflicts "net.ipv4.tcp_congestion_control"

    # Применяем настройки
    if ! sysctl -p &>> "$LOG_FILE"; then
        echo -e "\033[0;31mОшибка: Не удалось применить настройки sysctl.\033[0m"
        log_action "Failed to enable BBR (sysctl -p returned an error)."
        return 1
    fi

    echo -e "\033[0;32mBBR успешно включён.\033[0m"
    log_action "BBR enabled successfully."

    echo "Проверьте вывод: sysctl net.ipv4.tcp_congestion_control"
    echo -e "\033[0;33mДля полного применения настроек может потребоваться перезагрузка.\033[0m"
    read -p "Нажмите Enter, чтобы вернуться в главное меню..."
}


disable_bbr() {
    log_action "Attempting to disable BBR..."
    
    local current_qdisc
    local current_congestion

    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    current_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)

    echo -e "Текущие параметры:"
    echo -e "  net.core.default_qdisc = ${current_qdisc:-<не задан>}"
    echo -e "  net.ipv4.tcp_congestion_control = ${current_congestion:-<не задан>}"

    if [[ "$current_congestion" == "bbr" ]]; then
        backup_file /etc/sysctl.conf
        
        # Удаляем старые параметры BBR
        safe_sed_remove "net.core.default_qdisc=fq" /etc/sysctl.conf
        safe_sed_remove "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf
        
        # Устанавливаем CUBIC
        if grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
            sed -i 's/net.ipv4.tcp_congestion_control=.*/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf
        else
            echo "net.ipv4.tcp_congestion_control=cubic" >> /etc/sysctl.conf
        fi

        check_sysctl_d_conflicts "net.ipv4.tcp_congestion_control"

        if ! sysctl -p &>> "$LOG_FILE"; then
            echo -e "\033[0;31mОшибка: Не удалось применить настройки sysctl при отключении BBR.\033[0m"
            log_action "Failed to disable BBR (sysctl -p returned an error)."
        else
            echo -e "\033[0;32mBBR отключён, включён CUBIC.\033[0m"
            log_action "BBR disabled successfully."

            # Проверяем применённые настройки
            local new_congestion
            new_congestion=$(sysctl -n net.ipv4.tcp_congestion_control)
            if [[ "$new_congestion" == "cubic" ]]; then
                echo -e "\033[0;32mНастройки успешно применены. CUBIC активен.\033[0m"
            else
                echo -e "\033[0;31mОшибка: Настройки не применились. Проверьте файл /etc/sysctl.conf.\033[0m"
            fi
        fi
    else
        echo -e "\033[0;33mBBR не включён. Ничего отключать не нужно.\033[0m"
    fi

    echo -e "\033[0;33mДля полного применения настроек может потребоваться перезагрузка.\033[0m"
    read -p "Нажмите Enter, чтобы вернуться в главное меню..."
}

# Функция для отображения статуса BBR
function show_bbr_status {
    echo "$(sysctl net.ipv4.tcp_congestion_control)"
    read -p "Нажмите Enter, чтобы вернуться в главное меню..."
}

# --------------------------------------------------
# (П.7) ОПТИМИЗАЦИЯ КОРОТКИХ СОЕДИНЕНИЙ
#      + ВОЗМОЖНОСТЬ СОХРАНЕНИЯ BBR
# --------------------------------------------------
# По умолчанию убираем BBR и ставим cubic.
# Если хотите оставить BBR — установите USE_BBR_FOR_SHORT_CONN=true.

USE_BBR_FOR_SHORT_CONN="false"

configure_short_connections() {
    log_action "Configuring short connections optimization..."
    echo "=== Начинаем оптимизацию коротких соединений ===" | tee -a "$LOG_FILE"

    local LIMITS_FILE="/etc/security/limits.conf"
    local SYSCTL_FILE="/etc/sysctl.conf"

    backup_file "$LIMITS_FILE"
    backup_file "$SYSCTL_FILE"

    # (П.7) Если не хотим BBR для коротких соединений — удаляем
    if [[ "$USE_BBR_FOR_SHORT_CONN" == "false" ]]; then
        safe_sed_remove "net.core.default_qdisc=fq" "$SYSCTL_FILE"
        safe_sed_remove "net.ipv4.tcp_congestion_control=bbr" "$SYSCTL_FILE"
        log_action "BBR строки удалены, переходим на cubic для коротких соединений."
    else
        echo "Сохраняем BBR для коротких соединений (USE_BBR_FOR_SHORT_CONN=true)."
        log_action "BBR оставлен для коротких соединений."
    fi

    # 1) Обновление /etc/security/limits.conf
    sed -i '/nofile/d' "$LIMITS_FILE"
    if [[ $? -ne 0 ]]; then
        echo "Ошибка при удалении строк nofile в $LIMITS_FILE"
        log_action "Ошибка sed при удалении nofile в $LIMITS_FILE (short connections)."
    fi
    {
      echo "* soft nofile 51200"
      echo "* hard nofile 51200"
      echo "root soft nofile 51200"
      echo "root hard nofile 51200"
    } >> "$LIMITS_FILE"

    # 2) Удаляем старый блок short_conn_optim
    safe_sed_remove "^# short_conn_optim start" "$SYSCTL_FILE"
    # Заодно уберём всё до '# short_conn_optim end'
    # Чтоб убрать блок целиком, используем диапазон:
    sed -i '/^# short_conn_optim start/,/^# short_conn_optim end/d' "$SYSCTL_FILE"

    # 3) Вставляем новые параметры
    cat <<EOF >> "$SYSCTL_FILE"

# short_conn_optim start
# Параметры, оптимизированные под короткие соединения.

# Уменьшаем время, в течение которого сокеты висят в FIN-WAIT/TIME-WAIT
net.ipv4.tcp_fin_timeout = 10

# Разрешаем повторное использование сокетов в TIME_WAIT
net.ipv4.tcp_tw_reuse = 1

# Расширяем диапазон локальных портов
net.ipv4.ip_local_port_range = 1024 65000

# Включаем TCP Fast Open (3 = и клиент, и сервер)
net.ipv4.tcp_fastopen = 3

# Защита от SYN-флуд атак
net.ipv4.tcp_syncookies = 1

# Отключаем "медленный старт" после простоя
net.ipv4.tcp_slow_start_after_idle = 0

# Алгоритм управления перегрузкой — cubic (если не оставили BBR выше)
net.ipv4.tcp_congestion_control = cubic

# Дополнительные настройки очередей
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 4096

# short_conn_optim end
EOF

    # (П.6) Проверим конфликты в /etc/sysctl.d для ключевых параметров
    check_sysctl_d_conflicts "net.core.default_qdisc"
    check_sysctl_d_conflicts "net.ipv4.tcp_congestion_control"

    # 4) Применяем sysctl
    if ! sysctl -p "$SYSCTL_FILE" &>> "$LOG_FILE"; then
        echo "Ошибка: не удалось применить настройки sysctl (короткие соединения)."
        log_action "Failed to apply short connections sysctl config."
    else
        echo "Настройки для коротких соединений успешно применены."
        log_action "Short connections optimization applied."
    fi

    ask_for_reboot
}

# --------------------------------------------------
#    ОПТИМИЗАЦИЯ ДЛИТЕЛЬНЫХ СОЕДИНЕНИЙ
# --------------------------------------------------
configure_long_connections() {
    log_action "Configuring long connections optimization..."
    echo "=== Начинаем оптимизацию длительных соединений ===" | tee -a "$LOG_FILE"

    local LIMITS_FILE="/etc/security/limits.conf"
    local SYSCTL_FILE="/etc/sysctl.conf"

    backup_file "$LIMITS_FILE"
    backup_file "$SYSCTL_FILE"

    sed -i '/nofile/d' "$LIMITS_FILE"
    if [[ $? -ne 0 ]]; then
        echo "Ошибка при удалении строк nofile в $LIMITS_FILE"
        log_action "Ошибка sed при удалении nofile в $LIMITS_FILE (long connections)"
    fi
    {
      echo "* soft nofile 51200"
      echo "* hard nofile 51200"
      echo "root soft nofile 51200"
      echo "root hard nofile 51200"
    } >> "$LIMITS_FILE"

    # Удаляем блок short_conn_optim, чтобы исключить конфликт
    sed -i '/^# short_conn_optim start/,/^# short_conn_optim end/d' "$SYSCTL_FILE"

    # Добавляем блок с длинными соединениями
    cat <<EOF >> "$SYSCTL_FILE"

# long_conn_optim start
# Параметры, оптимизированные для длительных соединений (пример).

fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 10000
net.core.somaxconn = 4096
net.core.default_qdisc = fq
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 1800
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_max_orphans = 32768
net.ipv4.udp_mem = 25600 51200 102400
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3

# long_conn_optim end
EOF

    check_sysctl_d_conflicts "net.core.default_qdisc"
    check_sysctl_d_conflicts "net.ipv4.tcp_congestion_control"

    if ! sysctl -p &>> "$LOG_FILE"; then
        echo "Ошибка: не удалось применить настройки sysctl (long connections)."
        log_action "Failed to apply long connections sysctl config."
    else
        echo "Настройки для длительных соединений успешно применены."
        log_action "Long connections optimization applied."
    fi

    ask_for_reboot
}

# --------------------------------------------------
#   МЕНЮ ВЫБОРА ТИПА НАГРУЗКИ
# --------------------------------------------------
load_type_menu() {
    while true; do
        echo "Выберите тип нагрузки сети сервера:"
        echo "1) Короткие соединения (например, веб-серфинг, API)"
        echo "2) Длительные соединения (например, стриминг, VoIP, CDN)"
        echo "3) Стандартные настройки (Восстановить бэкап /etc/sysctl.conf и /etc/security/limits.conf)"
        echo "4) Выйти в главное меню"
        read -rp "Введите номер (1, 2, 3, или 4): " type_choice

        case $type_choice in
            1) configure_short_connections ;;
            2) configure_long_connections ;;
            3)
                echo "Восстановление стандартных настроек (BBR/limits)..."
                restore_backup /etc/sysctl.conf
                restore_backup /etc/security/limits.conf
                echo "Применение стандартных настроек..."
                if ! sysctl -p &>> "$LOG_FILE"; then
                    echo "Ошибка: не удалось применить стандартные настройки sysctl."
                    log_action "Failed to apply default sysctl config."
                else
                    echo "Стандартные настройки применены."
                    log_action "Default sysctl config applied."
                fi
                ask_for_reboot
                ;;
            4) return ;;
            *) echo "Неверный выбор. Попробуйте снова.";;
        esac
    done
}

# --------------------------------------------------
#   ГЛАВНОЕ МЕНЮ
# --------------------------------------------------
main_menu() {
    while true; do
        echo "Главное меню:"
        echo "1) Включить BBR"
        echo "2) Выключить BBR"
        echo "3) Статус BBR"
        echo "4) Настройки BBR/сети (выбрать тип нагрузки)"
        echo "5) Выход"
        read -rp "Введите номер действия (1/2/3/4/5): " action_choice

        case $action_choice in
            1) enable_bbr ;;
            2) disable_bbr ;;
            3) show_bbr_status ;;
            4) load_type_menu ;;
            5)
                echo "Выход из скрипта."
                log_action "Скрипт завершён пользователем."
                break
                ;;
            *) echo "Неверный выбор. Попробуйте снова.";;
        esac
    done
}

# Запуск главного меню при старте скрипта
main_menu
