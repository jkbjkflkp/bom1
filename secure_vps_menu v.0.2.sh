#!/bin/bash

#######################################################
#  Скрипт для настройки безопасности VPS
#  Бом (меню-версия с help)
#######################################################

###########################
#  ПУТЬ К ФАЙЛУ ЛОГА
###########################
LOGFILE="/var/log/secure_vps_script.log"

###########################
#  ФУНКЦИЯ ЛОГГИРОВАНИЯ
###########################
function log() {
    # Записываем сообщение в консоль и параллельно добавляем в лог-файл
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOGFILE"
}

#######################################################
#  Проверка, что скрипт запущен под root
#######################################################
if [ "$EUID" -ne 0 ]; then
    log "Пожалуйста, запустите скрипт под root."
    log "Например: sudo ./secure_vps_menu_root.sh"
    exit 1
fi

#######################################################
# 1. Функция вывода справки (usage)
#######################################################
function print_help() {
    log "Использование: $0 [опции]"
    log
    log "Опции:"
    log "  -h, --help        Показать эту справку и выйти"
    log
    log "Этот скрипт предоставляет меню для настройки безопасности сервера."
    log "Скрипт должен выполняться от root (без запроса sudo-пароля)."
    log
    log "Основные возможности:"
    log "  1) Обновить систему"
    log "  2) Изменить пароль root"
    log "  3) Управление пользователями (создание, изменение паролей, sudo без пароля)"
    log "  4) Настройка SSH (включение/выключение root-доступа)"
    log "  5) Смена SSH-порта"
    log "  6) Настроить ufw"
    log "  7) Настроить fail2ban"
    log "  8) Управление сервисами (например, qemu-guest-agent)"
    log
    log "Пример запуска:"
    log "  $0                # (если вы уже под root)"
    log "  sudo $0           # или sudo, чтобы стать root"
    log "  $0 --help         # вывод справки и завершение"
    log
}

#######################################################
# 2. Переменные для SSH (если выбрано ssh-подключение)
#######################################################
SSH_HOST=""
SSH_USER=""
SSH_PORT=""
SSH_PASSWORD=""

#######################################################
#  Зарезервированные имена (для проверки user name)
#######################################################
RESERVED_USERNAMES=(root bin daemon adm lp sync shutdown halt mail news uucp operator games ftp nobody systemd-timesync systemd-network systemd-resolve systemd-bus-proxy sys log uuidd admin)

#######################################################
#  ФУНКЦИИ ДЛЯ SSH/ЛОКАЛЬНОГО ВЫПОЛНЕНИЯ
#######################################################
function ssh_command() {
    local cmd=$1
    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "$cmd"
}

function run_command() {
    if [ "$MODE" == "ssh" ]; then
        ssh_command "$1"
    else
        eval "$1"
    fi
}

#######################################################
#  ФУНКЦИЯ ПРОВЕРКИ ИМЕНИ ПОЛЬЗОВАТЕЛЯ
#######################################################
function validate_username() {
    local username=$1
    if [[ ${#username} -lt 1 || ${#username} -gt 32 ]]; then
        log "Имя пользователя должно быть от 1 до 32 символов."
        return 1
    fi
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log "Имя пользователя должно начинаться с буквы или подчеркивания, и содержать только строчные буквы, цифры, дефисы и подчеркивания."
        return 1
    fi
    for reserved in "${RESERVED_USERNAMES[@]}"; do
        if [[ "$username" == "$reserved" ]]; then
            log "Имя пользователя '$username' является зарезервированным."
            return 1
        fi
    done
    return 0
}

#######################################################
#  ФУНКЦИЯ ПРОВЕРКИ ПАРОЛЯ
#######################################################
function validate_password() {
    local password=$1
    local valid=true

    if [[ ${#password} -lt 12 ]]; then
        log "Пароль должен быть не менее 12 символов."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[a-zа-я]"; then
        log "Пароль должен содержать хотя бы одну букву нижнего регистра (латинскую или русскую)."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[A-ZА-Я]"; then
        log "Пароль должен содержать хотя бы одну букву верхнего регистра (латинскую или русскую)."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[0-9]"; then
        log "Пароль должен содержать хотя бы одну цифру."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[[:punct:]]"; then
        log "Пароль должен содержать хотя бы один специальный символ."
        valid=false
    fi

    if ! $valid; then
        return 1
    fi
    return 0
}

#######################################################
#  ФУНКЦИЯ ИЗМЕНЕНИЯ ПАРОЛЯ ПОЛЬЗОВАТЕЛЯ
#######################################################
function change_user_password() {
    local username=$1
    while true; do
        read -s -p "Введите новый пароль для пользователя $username: " password
        echo
        validate_password "$password" || continue

        read -s -p "Повторите новый пароль для пользователя $username: " password_confirm
        echo
        if [ "$password" != "$password_confirm" ]; then
            log "Пароли не совпадают. Попробуйте снова."
            continue
        fi
        break
    done
    run_command "echo '$username:$password' | chpasswd"
    if [ $? -eq 0 ]; then
        log "Пароль для пользователя $username успешно изменен."
    else
        log "Не удалось изменить пароль для пользователя $username."
    fi
}

#######################################################
#  ДОБАВИТЬ SUDO БЕЗ ПАРОЛЯ
#######################################################
function add_user_nopasswd() {
    local username=$1
    run_command "echo '$username ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/$username"
    log "Пользователь $username может выполнять sudo без пароля."
}

#######################################################
#  УДАЛИТЬ SUDO БЕЗ ПАРОЛЯ
#######################################################
function remove_user_nopasswd() {
    local username=$1
    run_command "rm -f /etc/sudoers.d/$username"
    log "У пользователя $username убраны права sudo без пароля."
}

#######################################################
#  СОЗДАТЬ ПОЛЬЗОВАТЕЛЯ
#######################################################
function create_user() {
    local username=$1
    local password=$2
    local nopass=$3

    run_command "adduser --disabled-password --gecos '' $username"
    run_command "echo '$username:$password' | chpasswd"
    run_command "usermod -aG sudo $username"
    if [ "$nopass" == "yes" ]; then
        add_user_nopasswd "$username"
    fi
    log "Пользователь $username создан."
}

#######################################################
#  ПЕРЕЗАПУСТИТЬ SSH
#######################################################
function restart_ssh_service() {
    if run_command "systemctl list-units --type=service | grep -q sshd.service"; then
        run_command "systemctl restart sshd"
    else
        run_command "systemctl restart ssh"
    fi
}

#######################################################
#  ПРОВЕРКА ПОРТА SSH (1024..65535)
#######################################################
function validate_ssh_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]]; then
        return 0
    else
        return 1
    fi
}

#######################################################
#  ОТКЛЮЧИТЬ UFW, ЕСЛИ АКТИВЕН
#######################################################
function disable_ufw_if_active() {
    if run_command "ufw status | grep -q 'Status: active'"; then
        log "UFW активен. Отключаем UFW перед сменой порта SSH."
        run_command "ufw disable"
    fi
}

#######################################################
# 1) ОБНОВИТЬ СИСТЕМУ
#######################################################
function update_system() {
    log "Обновляем систему..."
    run_command "bash -c 'cat <<EOF | debconf-set-selections
* libraries/restart-without-asking boolean true
grub-pc grub-pc/install_devices multiselect /dev/sda
grub-pc grub-pc/install_devices_disks_changed multiselect /dev/sda
linux-base linux-base/removing-title2 boolean true
linux-base linux-base/removing-title boolean true
EOF'"

    run_command "DEBIAN_FRONTEND=noninteractive apt update && \
                 DEBIAN_FRONTEND=noninteractive apt upgrade -yq && \
                 DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::='--force-confdef' \
                   -o Dpkg::Options::='--force-confold' dist-upgrade -yq && \
                 DEBIAN_FRONTEND=noninteractive apt install -y unattended-upgrades && \
                 dpkg-reconfigure -f noninteractive unattended-upgrades && \
                 DEBIAN_FRONTEND=noninteractive unattended-upgrade"

    log "Обновление завершено."
}

#######################################################
# 2) ИЗМЕНИТЬ ПАРОЛЬ ROOT
#######################################################
function change_root_password_menu() {
    local ROOT_PASSWORD
    while true; do
        read -s -p "Введите новый пароль для root: " ROOT_PASSWORD
        echo
        validate_password "$ROOT_PASSWORD" || continue

        read -s -p "Повторите новый пароль: " ROOT_PASSWORD_CONFIRM
        echo
        if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
            log "Пароли не совпадают. Попробуйте снова."
            continue
        fi
        break
    done

    run_command "echo 'root:$ROOT_PASSWORD' | chpasswd"
    if [ $? -eq 0 ]; then
        log "Пароль root успешно изменен."
    else
        log "Не удалось изменить пароль root."
    fi
}

#######################################################
# 3) УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ (ПОДМЕНЮ)
#######################################################
function manage_users() {
    while true; do
        log "------------------------------------"
        log "Управление пользователями:"
        log "1) Создать нового пользователя"
        log "2) Изменить пароль существующего пользователя"
        log "3) Добавить/убрать sudo без пароля"
        log "0) Назад в главное меню"
        log "------------------------------------"
        read -p "Выберите действие: " user_choice

        case "$user_choice" in
            1)
                while true; do
                    read -p "Введите имя пользователя: " username
                    validate_username "$username" || continue
                    if id "$username" &>/dev/null; then
                        log "Пользователь $username уже существует."
                        break
                    fi
                    local password password_confirm
                    while true; do
                        read -s -p "Введите пароль: " password
                        echo
                        validate_password "$password" || continue

                        read -s -p "Повторите пароль: " password_confirm
                        echo
                        if [ "$password" != "$password_confirm" ]; then
                            log "Пароли не совпадают. Попробуйте снова."
                            continue
                        fi
                        break
                    done

                    read -p "Разрешить выполнение sudo без пароля? (yes/no): " nopass
                    if [[ "$nopass" =~ ^(yes|y)$ ]]; then
                        create_user "$username" "$password" "yes"
                    else
                        create_user "$username" "$password" "no"
                    fi
                    break
                done
                ;;
            2)
                read -p "Введите имя пользователя: " username
                if id "$username" &>/dev/null; then
                    change_user_password "$username"
                else
                    log "Пользователь $username не найден!"
                fi
                ;;
            3)
                read -p "Введите имя пользователя: " username
                if id "$username" &>/dev/null; then
                    if grep -q "$username ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/* 2>/dev/null; then
                        log "У пользователя $username уже есть sudo без пароля."
                        read -p "Убрать эти права? (yes/no): " remove_it
                        if [[ "$remove_it" =~ ^(yes|y)$ ]]; then
                            remove_user_nopasswd "$username"
                        fi
                    else
                        log "У пользователя $username нет sudo без пароля."
                        read -p "Добавить эти права? (yes/no): " add_it
                        if [[ "$add_it" =~ ^(yes|y)$ ]]; then
                            add_user_nopasswd "$username"
                        fi
                    fi
                else
                    log "Пользователь $username не найден!"
                fi
                ;;
            0)
                break
                ;;
            *)
                log "Некорректный выбор!"
                ;;
        esac
    done
}

#######################################################
# 4) НАСТРОЙКА SSH (ROOT ДОСТУП)
#######################################################
function configure_root_ssh() {
    local ROOT_SSH_STATUS
    ROOT_SSH_STATUS=$(run_command "grep '^PermitRootLogin' /etc/ssh/sshd_config")

    log "Текущее значение: $ROOT_SSH_STATUS"
    log "1) Разрешить root по SSH"
    log "2) Запретить root по SSH"
    log "0) Назад"
    read -p "Выберите пункт: " choice
    case "$choice" in
        1)
            run_command "sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config"
            restart_ssh_service
            log "Root по SSH разрешён."
            ;;
        2)
            run_command "sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
            restart_ssh_service
            log "Root по SSH запрещён."
            ;;
        0) ;;
        *)
            log "Некорректный выбор!"
            ;;
    esac
}

#######################################################
#    БЕЗОПАСНАЯ СМЕНА SSH-ПОРТА (safe_change_ssh_port)
#######################################################
function safe_change_ssh_port() {
    local OLD_PORT="$1"
    local NEW_PORT="$2"

    # 1. Проверка, что скрипт запущен под root
    if [ "$EUID" -ne 0 ]; then
        log "Пожалуйста, запустите скрипт под root или через sudo."
        return 1
    fi

    # 2. Валидация введённых портов
    if ! [[ "$OLD_PORT" =~ ^[0-9]+$ ]] || ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]]; then
        log "ОШИБКА: Значения порта должны быть целыми числами."
        return 1
    fi
    if [ "$OLD_PORT" -lt 1 ] || [ "$OLD_PORT" -gt 65535 ] ||
       [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
        log "ОШИБКА: Порт должен быть в диапазоне 1..65535."
        return 1
    fi
    if [ "$OLD_PORT" -eq "$NEW_PORT" ]; then
        log "ОШИБКА: Новый порт совпадает со старым. Изменение не требуется."
        return 1
    fi

    local SSHD_CONFIG="/etc/ssh/sshd_config"
    if [ ! -f "$SSHD_CONFIG" ]; then
        log "ОШИБКА: Файл $SSHD_CONFIG не найден!"
        return 1
    fi

    local BACKUP_FILE="${SSHD_CONFIG}.bak_$(date +%Y%m%d_%H%M%S)"
    cp "$SSHD_CONFIG" "$BACKUP_FILE"
    log "Создана резервная копия: $BACKUP_FILE"

    # 4. Проверяем, не занят ли новый порт другим процессом
    if lsof -i :"$NEW_PORT" &>/dev/null; then
        log "ОШИБКА: Порт $NEW_PORT уже используется другим процессом."
        return 1
    fi

    # 5. Предварительно открыть новый порт в UFW, если используется
    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            log "UFW активен. Добавляем правило для нового порта $NEW_PORT..."
            ufw allow "$NEW_PORT"/tcp
        fi
    fi

    # 6. Меняем строку Port в sshd_config
    if grep -q '^Port ' "$SSHD_CONFIG"; then
        sed -i "s/^Port .*/Port $NEW_PORT/" "$SSHD_CONFIG"
    else
        echo "Port $NEW_PORT" >> "$SSHD_CONFIG"
    fi

    # 7. Перезапускаем SSH
    log "Перезапускаем SSH..."
    if systemctl list-unit-files | grep -q ssh.service; then
        systemctl restart ssh
    else
        systemctl restart sshd
    fi

    # 8. Проверяем, слушает ли SSH на новом порту
    sleep 2
    if ! lsof -i :"$NEW_PORT" &>/dev/null; then
        log "ВНИМАНИЕ: Кажется, SSH не слушает на порту $NEW_PORT!"
        log "Восстанавливаем предыдущий конфиг..."
        mv "$BACKUP_FILE" "$SSHD_CONFIG"
        systemctl restart ssh || systemctl restart sshd
        return 1
    fi
    log "Порт SSH успешно изменён на $NEW_PORT."

    # 9. (Опционально) Закрыть старый порт в UFW
    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            read -p "Отключить старый порт $OLD_PORT в UFW? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                ufw deny "$OLD_PORT"/tcp
                log "Старый порт $OLD_PORT в UFW закрыт."
            fi
        fi
    fi

    log "Готово! Теперь SSH работает на порту $NEW_PORT."
}

#######################################################
# 5) СМЕНИТЬ SSH-ПОРТ (ОБНОВЛЁННАЯ ФУНКЦИЯ)
#######################################################
function change_ssh_port_menu() {
    local CURRENT_SSH_PORT=22
    read -p "Текущий SSH-порт (по умолчанию 22). Если вы уже меняли его вручную, введите реальный порт: " CURRENT_SSH_PORT_INPUT
    if [ -n "$CURRENT_SSH_PORT_INPUT" ]; then
        CURRENT_SSH_PORT=$CURRENT_SSH_PORT_INPUT
    fi

    log "Текущий порт: $CURRENT_SSH_PORT"
    read -p "Введите новый порт (1024..65535): " NEW_SSH_PORT

    safe_change_ssh_port "$CURRENT_SSH_PORT" "$NEW_SSH_PORT"
}

#######################################################
# 6) НАСТРОЙКА UFW
#######################################################
function configure_ufw() {
    run_command "apt install -yq ufw"
    read -p "Введите SSH-порт, который нужно разрешить (по умолчанию 22): " port
    [ -z "$port" ] && port=22
    run_command "ufw allow $port/tcp"
    run_command "ufw enable"
    log "ufw настроен и включен."
}

#######################################################
# 7) НАСТРОЙКА FAIL2BAN
#######################################################
function configure_fail2ban() {
    run_command "apt install -yq fail2ban"
    run_command "systemctl enable fail2ban"
    run_command "systemctl start fail2ban"

    read -p "Введите SSH-порт, который нужно прописать в fail2ban (по умолчанию 22): " port
    [ -z "$port" ] && port=22

    run_command "bash -c 'cat <<EOT > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = $port
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
EOT'"

    run_command "systemctl restart fail2ban"
    log "fail2ban установлен и настроен."
}

#######################################################
# 8) УПРАВЛЕНИЕ СЕРВИСАМИ (ПРИМЕР: qemu-guest-agent)
#######################################################
function manage_services() {
    local SERVICES=("qemu-guest-agent")
    for service in "${SERVICES[@]}"; do
        if dpkg -l | grep -qw "$service"; then
            local SERVICE_STATUS
            SERVICE_STATUS=$(run_command "systemctl is-active $service")
            log "Сервис $service найден, статус: $SERVICE_STATUS"
            if [ "$SERVICE_STATUS" == "active" ]; then
                log "1) Остановить, отключить и замаскировать"
                log "2) Оставить как есть"
                read -p "Ваш выбор (1/2)? " svc_choice
                if [ "$svc_choice" == "1" ]; then
                    run_command "systemctl stop $service"
                    run_command "systemctl disable $service"
                    run_command "systemctl mask $service"
                    log "$service остановлен, отключён и замаскирован."
                fi
            else
                log "Сервис $service не активен."
                log "1) Включить и запустить"
                log "2) Оставить как есть"
                read -p "Ваш выбор (1/2)? " svc_choice
                if [ "$svc_choice" == "1" ]; then
                    run_command "systemctl unmask $service"
                    run_command "systemctl enable $service"
                    run_command "systemctl start $service"
                    log "$service включён и активен."
                fi
            fi
        else
            log "Сервис $service не установлен в системе."
        fi
    done
}

#######################################################
#  ФУНКЦИЯ ПЕЧАТИ МЕНЮ (ПРЕЖДЕ БЫЛО show_menu)
#######################################################
function print_menu() {
    log "========================="
    log "     Главное меню"
    log "========================="
    log "1) Обновить систему"
    log "2) Изменить пароль root"
    log "3) Управление пользователями"
    log "4) Настройка SSH (root доступ)"
    log "5) Сменить SSH-порт"
    log "6) Настроить ufw"
    log "7) Настроить fail2ban"
    log "8) Управлять сервисами (qemu-guest-agent)"
    log "0) Выход"
    log "========================="
}

#######################################################
#  ОСНОВНОЙ ЦИКЛ МЕНЮ
#######################################################
function menu_loop() {
    while true; do
        print_menu
        read -p "Выберите пункт: " choice
        case "$choice" in
            1) update_system ;;
            2) change_root_password_menu ;;
            3) manage_users ;;
            4) configure_root_ssh ;;
            5) change_ssh_port_menu ;;
            6) configure_ufw ;;
            7) configure_fail2ban ;;
            8) manage_services ;;
            0)
                log "Выход из скрипта."
                break
                ;;
            *)
                log "Некорректный выбор!"
                ;;
        esac
        log
        read -p "Нажмите Enter, чтобы вернуться в меню..." dummy
    done
}

#######################################################
#  ГЛАВНАЯ ФУНКЦИЯ
#######################################################
function main() {
    # Проверим аргументы на предмет -h/--help
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print_help
        exit 0
    fi

    log "Выберите режим работы:"
    log " - local: если вы уже вошли на сервер (под root или с sudo) и хотите настроить именно эту машину."
    log " - ssh:   если вы хотите, чтобы скрипт подключался к другому серверу по SSH."
    log

    echo -en "Введите \e[32mlocal\e[0m или ssh (затем нажмите Enter, чтобы продолжить): "
    read MODE

    if [ "$MODE" == "ssh" ]; then
        if [ -z "$SSH_HOST" ]; then
            read -p "Введите хост SSH: " SSH_HOST
        fi
        if [ -z "$SSH_USER" ]; then
            read -p "Введите имя пользователя SSH: " SSH_USER
        fi
        if [ -z "$SSH_PASSWORD" ]; then
            read -s -p "Введите пароль SSH: " SSH_PASSWORD
            echo
        fi
        if [ -z "$SSH_PORT" ]; then
            read -p "Введите порт SSH (по умолчанию 22): " SSH_PORT
            [ -z "$SSH_PORT" ] && SSH_PORT=22
        fi
    else
        MODE="local"
    fi

    menu_loop
}

# Запуск скрипта
main "$@"
