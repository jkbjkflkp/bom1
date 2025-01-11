#!/bin/bash

#######################################################
#  Скрипт для настройки безопасности VPS
#  Бом (меню-версия с help)
#######################################################

# Проверка, что скрипт запущен под root
if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите скрипт под root."
    echo "Например: sudo ./secure_vps_menu_root.sh"
    exit 1
fi

# ------------------------------------------------
# 1. Функция вывода справки (usage)
# ------------------------------------------------
function print_help() {
    echo "Использование: $0 [опции]"
    echo
    echo "Опции:"
    echo "  -h, --help        Показать эту справку и выйти"
    echo
    echo "Этот скрипт предоставляет меню для настройки безопасности сервера."
    echo "Скрипт должен выполняться от root (без запроса sudo-пароля)."
    echo
    echo "Основные возможности:"
    echo "  1) Обновить систему"
    echo "  2) Изменить пароль root"
    echo "  3) Управление пользователями (создание, изменение паролей, sudo без пароля)"
    echo "  4) Настройка SSH (включение/выключение root-доступа)"
    echo "  5) Смена SSH-порта"
    echo "  6) Настроить ufw"
    echo "  7) Настроить fail2ban"
    echo "  8) Управление сервисами (например, qemu-guest-agent)"
    echo
    echo "Пример запуска:"
    echo "  $0                # (если вы уже под root)"
    echo "  sudo $0           # или sudo, чтобы стать root"
    echo "  $0 --help         # вывод справки и завершение"
    echo
}

# ------------------------------------------------
# 2. Переменные для SSH (если выбрано ssh-подключение)
# ------------------------------------------------
SSH_HOST=""
SSH_USER=""
SSH_PORT=""
SSH_PASSWORD=""

# ------------------------------------------------
#  Зарезервированные имена (для проверки user name)
# ------------------------------------------------
RESERVED_USERNAMES=(root bin daemon adm lp sync shutdown halt mail news uucp operator games ftp nobody systemd-timesync systemd-network systemd-resolve systemd-bus-proxy sys log uuidd admin)

# ------------------------------------------------
#  Функции для SSH/локального выполнения
# ------------------------------------------------
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

# ------------------------------------------------
#  Функция проверки имени пользователя
# ------------------------------------------------
function validate_username() {
    local username=$1
    if [[ ${#username} -lt 1 || ${#username} -gt 32 ]]; then
        echo "Имя пользователя должно быть от 1 до 32 символов."
        return 1
    fi
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Имя пользователя должно начинаться с буквы или подчеркивания, и содержать только строчные буквы, цифры, дефисы и подчеркивания."
        return 1
    fi
    for reserved in "${RESERVED_USERNAMES[@]}"; do
        if [[ "$username" == "$reserved" ]]; then
            echo "Имя пользователя '$username' является зарезервированным."
            return 1
        fi
    done
    return 0
}

# ------------------------------------------------
#  Функция проверки пароля
# ------------------------------------------------
function validate_password() {
    local password=$1
    local valid=true

    if [[ ${#password} -lt 12 ]]; then
        echo "Пароль должен быть не менее 12 символов."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[a-zа-я]"; then
        echo "Пароль должен содержать хотя бы одну букву нижнего регистра (латинскую или русскую)."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[A-ZА-Я]"; then
        echo "Пароль должен содержать хотя бы одну букву верхнего регистра (латинскую или русскую)."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[0-9]"; then
        echo "Пароль должен содержать хотя бы одну цифру."
        valid=false
    fi

    if ! echo "$password" | grep -qP "[[:punct:]]"; then
        echo "Пароль должен содержать хотя бы один специальный символ."
        valid=false
    fi

    if ! $valid; then
        return 1
    fi
    return 0
}

# ------------------------------------------------
#  Функция изменения пароля пользователя
# ------------------------------------------------
function change_user_password() {
    local username=$1
    while true; do
        read -s -p "Введите новый пароль для пользователя $username: " password
        echo
        validate_password "$password" || continue

        read -s -p "Повторите новый пароль для пользователя $username: " password_confirm
        echo
        if [ "$password" != "$password_confirm" ]; then
            echo "Пароли не совпадают. Попробуйте снова."
            continue
        fi
        break
    done
    run_command "echo '$username:$password' | chpasswd"
    if [ $? -eq 0 ]; then
        echo "Пароль для пользователя $username успешно изменен."
    else
        echo "Не удалось изменить пароль для пользователя $username."
    fi
}

# ------------------------------------------------
#  Добавить sudo без пароля
# ------------------------------------------------
function add_user_nopasswd() {
    local username=$1
    run_command "echo '$username ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/$username"
    echo "Пользователь $username может выполнять sudo без пароля."
}

# ------------------------------------------------
#  Удалить sudo без пароля
# ------------------------------------------------
function remove_user_nopasswd() {
    local username=$1
    run_command "rm -f /etc/sudoers.d/$username"
    echo "У пользователя $username убраны права sudo без пароля."
}

# ------------------------------------------------
#  Создать пользователя
# ------------------------------------------------
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
    echo "Пользователь $username создан."
}

# ------------------------------------------------
#  Перезапустить SSH
# ------------------------------------------------
function restart_ssh_service() {
    if run_command "systemctl list-units --type=service | grep -q sshd.service"; then
        run_command "systemctl restart sshd"
    else
        run_command "systemctl restart ssh"
    fi
}

# ------------------------------------------------
#  Проверка порта SSH (1024..65535)
# ------------------------------------------------
function validate_ssh_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]]; then
        return 0
    else
        return 1
    fi
}

# ------------------------------------------------
#  Отключить ufw, если активен
# ------------------------------------------------
function disable_ufw_if_active() {
    if run_command "ufw status | grep -q 'Status: active'"; then
        echo "UFW активен. Отключаем UFW перед сменой порта SSH."
        run_command "ufw disable"
    fi
}

# ------------------------------------------------
# 1) Обновить систему
# ------------------------------------------------
function update_system() {
    echo "Обновляем систему..."
    run_command "echo '* libraries/restart-without-asking boolean true' | debconf-set-selections"
    run_command "echo 'grub-pc grub-pc/install_devices multiselect /dev/sda' | debconf-set-selections"
    run_command "echo 'grub-pc grub-pc/install_devices_disks_changed multiselect /dev/sda' | debconf-set-selections"
    run_command "echo 'linux-base linux-base/removing-title2 boolean true' | debconf-set-selections"
    run_command "echo 'linux-base linux-base/removing-title boolean true' | debconf-set-selections"

    run_command "DEBIAN_FRONTEND=noninteractive apt update && DEBIAN_FRONTEND=noninteractive apt upgrade -yq"
    run_command "DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade -yq"
    run_command "DEBIAN_FRONTEND=noninteractive apt install -y unattended-upgrades"
    run_command "dpkg-reconfigure -f noninteractive unattended-upgrades"
    run_command "DEBIAN_FRONTEND=noninteractive unattended-upgrade"

    echo "Обновление завершено."
}

# ------------------------------------------------
# 2) Изменить пароль root
# ------------------------------------------------
function change_root_password_menu() {
    local ROOT_PASSWORD
    while true; do
        read -s -p "Введите новый пароль для root: " ROOT_PASSWORD
        echo
        validate_password "$ROOT_PASSWORD" || continue

        read -s -p "Повторите новый пароль: " ROOT_PASSWORD_CONFIRM
        echo
        if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
            echo "Пароли не совпадают. Попробуйте снова."
            continue
        fi
        break
    done

    run_command "echo 'root:$ROOT_PASSWORD' | chpasswd"
    if [ $? -eq 0 ]; then
        echo "Пароль root успешно изменен."
    else
        echo "Не удалось изменить пароль root."
    fi
}

# ------------------------------------------------
# 3) Управление пользователями (подменю)
# ------------------------------------------------
function manage_users() {
    while true; do
        echo "------------------------------------"
        echo "Управление пользователями:"
        echo "1) Создать нового пользователя"
        echo "2) Изменить пароль существующего пользователя"
        echo "3) Добавить/убрать sudo без пароля"
        echo "0) Назад в главное меню"
        echo "------------------------------------"
        read -p "Выберите действие: " user_choice

        case "$user_choice" in
            1)
                while true; do
                    read -p "Введите имя пользователя: " username
                    validate_username "$username" || continue
                    if id "$username" &>/dev/null; then
                        echo "Пользователь $username уже существует."
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
                            echo "Пароли не совпадают. Попробуйте снова."
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
                    echo "Пользователь $username не найден!"
                fi
                ;;
            3)
                read -p "Введите имя пользователя: " username
                if id "$username" &>/dev/null; then
                    if grep -q "$username ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/* 2>/dev/null; then
                        echo "У пользователя $username уже есть sudo без пароля."
                        read -p "Убрать эти права? (yes/no): " remove_it
                        if [[ "$remove_it" =~ ^(yes|y)$ ]]; then
                            remove_user_nopasswd "$username"
                        fi
                    else
                        echo "У пользователя $username нет sudo без пароля."
                        read -p "Добавить эти права? (yes/no): " add_it
                        if [[ "$add_it" =~ ^(yes|y)$ ]]; then
                            add_user_nopasswd "$username"
                        fi
                    fi
                else
                    echo "Пользователь $username не найден!"
                fi
                ;;
            0)
                break
                ;;
            *)
                echo "Некорректный выбор!"
                ;;
        esac
    done
}

# ------------------------------------------------
# 4) Настройка SSH (root доступ)
# ------------------------------------------------
function configure_root_ssh() {
    local ROOT_SSH_STATUS
    ROOT_SSH_STATUS=$(run_command "grep '^PermitRootLogin' /etc/ssh/sshd_config")

    echo "Текущее значение: $ROOT_SSH_STATUS"
    echo "1) Разрешить root по SSH"
    echo "2) Запретить root по SSH"
    echo "0) Назад"
    read -p "Выберите пункт: " choice
    case "$choice" in
        1)
            run_command "sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config"
            restart_ssh_service
            echo "Root по SSH разрешён."
            ;;
        2)
            run_command "sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
            restart_ssh_service
            echo "Root по SSH запрещён."
            ;;
        0) ;;
        *)
            echo "Некорректный выбор!"
            ;;
    esac
}

# ------------------------------------------------
# 5) Сменить SSH-порт
# ------------------------------------------------
function change_ssh_port_menu() {
    local CURRENT_SSH_PORT=22
    read -p "Текущий порт (по умолчанию 22). Если вы уже меняли его вручную, введите реальный порт: " CURRENT_SSH_PORT_INPUT
    if [ -n "$CURRENT_SSH_PORT_INPUT" ]; then
        CURRENT_SSH_PORT=$CURRENT_SSH_PORT_INPUT
    fi

    echo "Текущий порт: $CURRENT_SSH_PORT"
    read -p "Введите новый порт (1024..65535): " NEW_SSH_PORT
    if validate_ssh_port "$NEW_SSH_PORT"; then
        disable_ufw_if_active
        if run_command "grep -q '^Port' /etc/ssh/sshd_config"; then
            run_command "sed -i 's/^Port.*/Port $NEW_SSH_PORT/' /etc/ssh/sshd_config"
        else
            run_command "echo 'Port $NEW_SSH_PORT' >> /etc/ssh/sshd_config"
        fi
        restart_ssh_service
        echo "Порт SSH изменён на $NEW_SSH_PORT."
    else
        echo "Недопустимый порт!"
    fi
}

# ------------------------------------------------
# 6) Настройка ufw
# ------------------------------------------------
function configure_ufw() {
    run_command "apt install -yq ufw"
    read -p "Введите SSH-порт, который нужно разрешить (по умолчанию 22): " port
    [ -z "$port" ] && port=22
    run_command "ufw allow $port/tcp"
    run_command "ufw enable"
    echo "ufw настроен и включен."
}

# ------------------------------------------------
# 7) Настройка fail2ban
# ------------------------------------------------
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
    echo "fail2ban установлен и настроен."
}

# ------------------------------------------------
# 8) Управление сервисами (пример: qemu-guest-agent)
# ------------------------------------------------
function manage_services() {
    local SERVICES=("qemu-guest-agent")
    for service in "${SERVICES[@]}"; do
        if dpkg -l | grep -qw "$service"; then
            SERVICE_STATUS=$(run_command "systemctl is-active $service")
            echo "Сервис $service найден, статус: $SERVICE_STATUS"
            if [ "$SERVICE_STATUS" == "active" ]; then
                echo "1) Остановить, отключить и замаскировать"
                echo "2) Оставить как есть"
                read -p "Ваш выбор (1/2)? " svc_choice
                if [ "$svc_choice" == "1" ]; then
                    run_command "systemctl stop $service"
                    run_command "systemctl disable $service"
                    run_command "systemctl mask $service"
                    echo "$service остановлен, отключён и замаскирован."
                fi
            else
                echo "Сервис $service не активен."
                echo "1) Включить и запустить"
                echo "2) Оставить как есть"
                read -p "Ваш выбор (1/2)? " svc_choice
                if [ "$svc_choice" == "1" ]; then
                    run_command "systemctl unmask $service"
                    run_command "systemctl enable $service"
                    run_command "systemctl start $service"
                    echo "$service включён и активен."
                fi
            fi
        else
            echo "Сервис $service не установлен в системе."
        fi
    done
}

# ------------------------------------------------
#  Показать меню
# ------------------------------------------------
function show_menu() {
    echo "========================="
    echo "     Главное меню"
    echo "========================="
    echo "1) Обновить систему"
    echo "2) Изменить пароль root"
    echo "3) Управление пользователями"
    echo "4) Настройка SSH (root доступ)"
    echo "5) Сменить SSH-порт"
    echo "6) Настроить ufw"
    echo "7) Настроить fail2ban"
    echo "8) Управлять сервисами (qemu-guest-agent)"
    echo "0) Выход"
    echo "========================="
}

# ------------------------------------------------
#  Главная функция
# ------------------------------------------------
function main() {
    # Проверим аргументы на предмет -h/--help
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print_help
        exit 0
    fi

    # --- Добавляем описание перед выбором режима ---
    echo "Выберите режим работы:"
    echo " - local: если вы уже вошли на сервер (под root или с sudo) и хотите настроить именно эту машину."
    echo " - ssh:   если вы хотите, чтобы скрипт подключался к другому серверу по SSH."
    echo

    # Здесь слово "local" будет зелёным, и добавляем уточнение про нажатие Enter
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

    while true; do
        show_menu
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
                echo "Выход из скрипта."
                break
                ;;
            *)
                echo "Некорректный выбор!"
                ;;
        esac
        echo
        read -p "Нажмите Enter, чтобы вернуться в меню..." dummy
    done
}

# Запуск скрипта
main "$@"
