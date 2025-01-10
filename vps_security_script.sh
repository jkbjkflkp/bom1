#!/bin/bash

# Скрипт для настройки безопасности VPS от Бом

# Переменные для SSH подключения (можно оставить пустыми для запроса при выполнении скрипта)
SSH_HOST=""
SSH_USER=""
SSH_PORT=""
SSH_PASSWORD=""

# Переменные для создания пользователей (можно оставить пустыми для запроса при выполнении скрипта)
declare -A USERS=(
    # ["namenewuser1"]="nameuser:passworduser:no"
    # ["namenewuser2"]="newuser:passworduser2:yes"
)

# Вопросы и ответы (можно оставить пустыми для запроса при выполнении скрипта)
UPDATE_SYSTEM=""  # yes/no
CHANGE_ROOT_PASSWORD=""  # yes/no
ROOT_PASSWORD=""
DISABLE_ROOT_SSH=""  # yes/no
CHANGE_SSH_PORT=""  # yes/no
NEW_SSH_PORT=""
CONFIGURE_UFW=""  # yes/no
CONFIGURE_FAIL2BAN=""  # yes/no
BLOCK_PING=""  # yes/no

# Зарезервированные имена
RESERVED_USERNAMES=(root bin daemon adm lp sync shutdown halt mail news uucp operator games ftp nobody systemd-timesync systemd-network systemd-resolve systemd-bus-proxy sys log uuidd admin)

# Функция для выполнения команды локально или через SSH
function run_command() {
    if [ "$MODE" == "ssh" ]; then
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -p $SSH_PORT "$SSH_USER@$SSH_HOST" "$1"
    else
        eval "$1"
    fi
}

# Функция для обновления системы
function update_system() {
    if [ -z "$UPDATE_SYSTEM" ]; then
        while true; do
            read -p "Обновить систему перед настройкой? (yes/no): " UPDATE_SYSTEM
            if [[ "$UPDATE_SYSTEM" =~ ^(yes|no|y|n)$ ]]; then
                break
            else
                echo "Ошибка ввода. Пожалуйста, введите 'yes' или 'no'."
            fi
        done
    fi

    if [[ "$UPDATE_SYSTEM" =~ ^(yes|y)$ ]]; then
        echo "Обновление системы..."
        run_command "sudo apt update && sudo apt upgrade -y"
        echo "Система обновлена."
    else
        echo "Обновление системы пропущено."
    fi
}

# Функция для смены пароля root
function change_root_password() {
    if [ -z "$CHANGE_ROOT_PASSWORD" ]; then
        while true; do
            read -p "Хотите изменить пароль root? (yes/no): " CHANGE_ROOT_PASSWORD
            if [[ "$CHANGE_ROOT_PASSWORD" =~ ^(yes|no|y|n)$ ]]; then
                break
            else
                echo "Ошибка ввода. Пожалуйста, введите 'yes' или 'no'."
            fi
        done
    fi

    if [[ "$CHANGE_ROOT_PASSWORD" =~ ^(yes|y)$ ]]; then
        while true; do
            read -s -p "Введите новый пароль root: " ROOT_PASSWORD
            echo
            read -s -p "Повторите новый пароль root: " ROOT_PASSWORD_CONFIRM
            echo
            if [ "$ROOT_PASSWORD" == "$ROOT_PASSWORD_CONFIRM" ]; then
                echo "Пароли совпадают. Применение изменений..."
                echo -e "$ROOT_PASSWORD
$ROOT_PASSWORD" | run_command "sudo passwd root"
                echo "Пароль root успешно изменен."
                break
            else
                echo "Пароли не совпадают. Попробуйте снова."
            fi
        done
    else
        echo "Смена пароля root пропущена."
    fi
}

# Функция для управления доступом root по SSH
function configure_root_ssh() {
    if [ -z "$DISABLE_ROOT_SSH" ]; then
        while true; do
            read -p "Отключить доступ root по SSH? (yes/no): " DISABLE_ROOT_SSH
            if [[ "$DISABLE_ROOT_SSH" =~ ^(yes|no|y|n)$ ]]; then
                break
            else
                echo "Ошибка ввода. Пожалуйста, введите 'yes' или 'no'."
            fi
        done
    fi

    if [[ "$DISABLE_ROOT_SSH" =~ ^(yes|y)$ ]]; then
        echo "Отключение доступа root по SSH..."
        run_command "sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config"
    else
        echo "Включение доступа root по SSH..."
        run_command "sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config"
    fi

    echo "Перезапуск службы SSH..."
    run_command "sudo systemctl restart sshd || sudo systemctl restart ssh"
}

# Функция для изменения порта SSH
function change_ssh_port() {
    if [ -z "$CHANGE_SSH_PORT" ]; then
        while true; do
            read -p "Хотите изменить порт SSH? (yes/no): " CHANGE_SSH_PORT
            if [[ "$CHANGE_SSH_PORT" =~ ^(yes|no|y|n)$ ]]; then
                break
            else
                echo "Ошибка ввода. Пожалуйста, введите 'yes' или 'no'."
            fi
        done
    fi

    if [[ "$CHANGE_SSH_PORT" =~ ^(yes|y)$ ]]; then
        while true; do
            read -p "Введите новый порт SSH: " NEW_SSH_PORT
            if [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ && $NEW_SSH_PORT -ge 1 && $NEW_SSH_PORT -le 65535 ]]; then
                break
            else
                echo "Ошибка ввода. Пожалуйста, введите допустимый номер порта (1-65535)."
            fi
        done

        echo "Изменение порта SSH на $NEW_SSH_PORT..."
        run_command "sudo sed -i 's/^Port.*/Port $NEW_SSH_PORT/' /etc/ssh/sshd_config"

        echo "Перезапуск службы SSH..."
        run_command "sudo systemctl restart sshd || sudo systemctl restart ssh"

        echo "Порт SSH успешно изменен."
    else
        echo "Изменение порта SSH пропущено."
    fi
}

# Функция для управления пользователями
function manage_users() {
    while true; do
        echo "Управление пользователями:"
        echo "1) Создать нового пользователя"
        echo "2) Сменить пароль существующего пользователя"
        echo "3) Добавить пользователя в группу sudo"
        echo "4) Разрешить выполнение команд без пароля"
        echo "5) Запретить выполнение команд без пароля"
        echo "6) Выйти из управления пользователями"

        read -p "Выберите действие (1-6): " USER_ACTION

        case $USER_ACTION in
            1)
                read -p "Введите имя нового пользователя: " NEW_USER
                if [[ " ${RESERVED_USERNAMES[@]} " =~ " $NEW_USER " ]]; then
                    echo "Имя пользователя зарезервировано. Выберите другое имя."
                    continue
                fi
                run_command "sudo adduser --gecos "" $NEW_USER"
                echo "Пользователь $NEW_USER успешно создан."
                ;;
            2)
                read -p "Введите имя пользователя для смены пароля: " EXISTING_USER
                run_command "sudo passwd $EXISTING_USER"
                echo "Пароль пользователя $EXISTING_USER успешно изменен."
                ;;
            3)
                read -p "Введите имя пользователя для добавления в sudo: " SUDO_USER
                run_command "sudo usermod -aG sudo $SUDO_USER"
                echo "Пользователь $SUDO_USER добавлен в группу sudo."
                ;;
            4)
                read -p "Введите имя пользователя для разрешения выполнения команд без пароля: " NOPASS_USER
                run_command "echo '$NOPASS_USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$NOPASS_USER"
                echo "Пользователю $NOPASS_USER разрешено выполнять команды без пароля."
                ;;
            5)
                read -p "Введите имя пользователя для запрета выполнения команд без пароля: " RESTRICT_USER
                run_command "sudo rm /etc/sudoers.d/$RESTRICT_USER"
                echo "Пользователю $RESTRICT_USER запрещено выполнять команды без пароля."
                ;;
            6)
                break
