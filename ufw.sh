#!/bin/bash

LOG_FILE="ufw_manager.log"
BEFORE_FILE="/etc/ufw/before.rules"
BEFORE_BACKUP_FILE="/etc/ufw/before.rules.bak"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_ufw_status() {
    if ! sudo ufw status | grep -q "Status: active"; then
        echo "UFW is not active. Please enable UFW and press Enter to continue."
        read
        exit 1
    fi
}

check_file_exists() {
    if [ ! -f "$BEFORE_FILE" ]; then
        echo "File $BEFORE_FILE does not exist. Press Enter to exit."
        read
        exit 1
    fi
}

create_backup_if_needed() {
    if [ ! -f "$BEFORE_BACKUP_FILE" ]; then
        sudo cp "$BEFORE_FILE" "$BEFORE_BACKUP_FILE"
        log "Backup of $BEFORE_FILE created as $BEFORE_BACKUP_FILE"
    fi
}

restore_from_backup() {
    if [ -f "$BEFORE_BACKUP_FILE" ]; then
        sudo cp "$BEFORE_BACKUP_FILE" "$BEFORE_FILE"
        log "Restored $BEFORE_FILE from $BEFORE_BACKUP_FILE"
        echo "Standard settings restored successfully. Press Enter to return to the main menu."
        read
    else
        echo "Backup file $BEFORE_BACKUP_FILE does not exist. Cannot restore. Press Enter to return to the main menu."
        read
    fi
}

check_icmp_rule() {
    if [ -s "$BEFORE_FILE" ] && grep -q "source-quench" "$BEFORE_FILE"; then
        echo "Изменения уже применены. Возвращение в главное меню."
        read
    else
        apply_changes
    fi
}

apply_changes() {
    create_backup_if_needed

    # Ensure necessary chains exist
    if ! sudo iptables -t filter -L ufw-logging-deny &> /dev/null; then
        echo "Chain ufw-logging-deny does not exist. Creating it..."
        sudo iptables -t filter -N ufw-logging-deny
        log "Created chain ufw-logging-deny"
    fi

    # Remove existing changes
    sudo sed -i '/\-A ufw-before-input -p icmp --icmp-type source-quench -j DROP/d' "$BEFORE_FILE"
    sudo sed -i '/\-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT/d' "$BEFORE_FILE"
    sudo sed -i '/\-A ufw-before-input -p icmp --icmp-type time-exceeded -j ACCEPT/d' "$BEFORE_FILE"
    sudo sed -i '/\-A ufw-before-input -p icmp --icmp-type parameter-problem -j ACCEPT/d' "$BEFORE_FILE"
    sudo sed -i '/\-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/d' "$BEFORE_FILE"
    sudo sed -i '/\-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j ACCEPT/d' "$BEFORE_FILE"
    sudo sed -i '/\-A ufw-before-forward -p icmp --icmp-type time-exceeded -j ACCEPT/d' "$BEFORE_FILE"
    sudo sed -i '/\-A ufw-before-forward -p icmp --icmp-type parameter-problem -j ACCEPT/d' "$BEFORE_FILE"
    sudo sed -i '/\-A ufw-before-forward -p icmp --icmp-type echo-request -j ACCEPT/d' "$BEFORE_FILE"

    # Apply new changes
    sudo sed -i '/# ok icmp codes for INPUT/a \
-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP \
-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP \
-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP \
-A ufw-before-input -p icmp --icmp-type echo-request -j DROP \
-A ufw-before-input -p icmp --icmp-type source-quench -j DROP' "$BEFORE_FILE"
    log "Applied changes directly to $BEFORE_FILE"

    sudo sed -i '/# ok icmp code for FORWARD/a \
-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j DROP \
-A ufw-before-forward -p icmp --icmp-type time-exceeded -j DROP \
-A ufw-before-forward -p icmp --icmp-type parameter-problem -j DROP \
-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP' "$BEFORE_FILE"
    log "Applied changes directly to $BEFORE_FILE"

    # Check for duplicates
    sudo awk '!seen[$0]++' "$BEFORE_FILE" | sudo tee "${BEFORE_FILE}.tmp" > /dev/null
    sudo mv "${BEFORE_FILE}.tmp" "$BEFORE_FILE"
    log "Removed duplicates from $BEFORE_FILE"

    # Reload UFW
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw reload
        if [ $? -eq 0 ]; then
            echo "Changes applied successfully. Press Enter to return to the main menu."
            read
        else
            echo "Failed to apply changes. Check logs for details. Press Enter to return to the main menu."
            read
        fi
    else
        echo "UFW is not active. Changes applied, but UFW was not reloaded. Press Enter to return to the main menu."
        read
    fi
}

main_menu() {
    while true; do
        clear
        echo "Main Menu"
        echo "1. Запрет пинга"
        echo "2. Стандартные настройки"
        echo "3. Логи"
        echo "4. Выход"
        echo "Выберите опцию:"
        read choice

        case $choice in
            1)
                check_ufw_status
                check_file_exists
                check_icmp_rule
                ;;
            2)
                restore_from_backup
                ;;
            3)
                if [ -f "$LOG_FILE" ]; then
                    less "$LOG_FILE"
                else
                    echo "Лог файл не существует. Press Enter to return к главному меню."
                    read
                fi
                ;;
            4)
                echo "Выход из программы. Press Enter."
                read
                exit 0
                ;;
            *)
                echo "Неверный выбор. Попробуйте снова. Press Enter."
                read
                ;;
        esac
    done
}

main_menu
