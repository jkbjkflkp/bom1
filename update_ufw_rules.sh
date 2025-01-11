#!/bin/bash

# Проверка, что скрипт выполняется с правами root
if [ "$EUID" -ne 0 ]; then
    echo "Этот скрипт должен выполняться с правами root. Завершение."
    exit 1
fi

# Переменная для пути к файлу (можно передать как аргумент)
RULES_FILE=${1:-/etc/ufw/before.rules}

# Проверяем, существует ли файл before.rules
if [ ! -f "$RULES_FILE" ]; then
    echo "Файл $RULES_FILE не найден. Завершение."
    exit 1
fi

# Проверяем, что путь соответствует ожидаемому файлу
if [[ ! "$RULES_FILE" =~ ^/etc/ufw/before.rules$ ]]; then
    echo "Путь к файлу не является допустимым. Разрешен только /etc/ufw/before.rules."
    exit 1
fi

# Проверяем права на запись в файл
if [ ! -w "$RULES_FILE" ]; then
    echo "Файл $RULES_FILE защищён от записи. Проверьте права доступа."
    exit 1
fi

# Проверяем доступность UFW
if ! command -v ufw &> /dev/null; then
    echo "UFW не установлен. Установите его и попробуйте снова."
    exit 1
fi

# Создаем резервную копию файла
BACKUP_FILE="${RULES_FILE}.bak"
echo "Создаем резервную копию: $BACKUP_FILE"
cp "$RULES_FILE" "$BACKUP_FILE"
if [ $? -ne 0 ]; then
    echo "Не удалось создать резервную копию. Завершение."
    exit 1
fi

# Функция для проверки ошибок
check_errors() {
    if [ $? -ne 0 ]; then
        echo "Произошла ошибка. Завершение скрипта."
        exit 1
    fi
}

# Проверяем наличие блоков в файле
if ! grep -q "# ok icmp codes for INPUT" "$RULES_FILE"; then
    echo "Блок # ok icmp codes for INPUT не найден. Завершение."
    exit 1
fi

if ! grep -q "# ok icmp codes for FORWARD" "$RULES_FILE"; then
    echo "Блок # ok icmp codes for FORWARD не найден. Завершение."
    exit 1
fi

# Проверяем наличие строки, чтобы избежать дублирования
if grep -q "-A ufw-before-input -p icmp --icmp-type source-quench -j DROP" "$RULES_FILE"; then
    echo "Строка уже существует, пропускаем добавление."
else
    sed -i '/# ok icmp codes for INPUT/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' "$RULES_FILE"
    check_errors

    # Проверяем, что строка была добавлена корректно
    if ! grep -q "-A ufw-before-input -p icmp --icmp-type source-quench -j DROP" "$RULES_FILE"; then
        echo "Не удалось добавить строку в файл. Проверьте вручную." | tee -a "$LOGFILE"
        exit 1
    fi
fi

# Заменяем ACCEPT на DROP в блоках
echo "Заменяем ACCEPT на DROP в блоках..."
sed -i '/# ok icmp codes for INPUT/,/# ok icmp codes for FORWARD/{s/ACCEPT/DROP/g}' "$RULES_FILE"
check_errors

# Проверяем свободное место перед применением UFW
if [ "$(df "$RULES_FILE" | tail -1 | awk '{print $4}')" -lt 1024 ]; then
    echo "Недостаточно места для выполнения операций. Освободите место и попробуйте снова."
    exit 1
fi

# Проверяем UFW на ошибки
ufw disable && ufw enable
check_errors

# Проверяем статус UFW
ufw status > /dev/null
if [ $? -ne 0 ]; then
    echo "UFW не удалось активировать. Проверьте настройки."
    exit 1
fi

# Логирование действий
LOGFILE="/var/log/update_ufw_rules.log"
echo "$(date): Создана резервная копия $BACKUP_FILE" >> "$LOGFILE"
echo "$(date): Строка -A ufw-before-input -p icmp --icmp-type source-quench -j DROP добавлена." >> "$LOGFILE"
echo "$(date): Заменены ACCEPT на DROP в блоках." >> "$LOGFILE"
echo "Все изменения успешно применены." | tee -a "$LOGFILE"
echo "Логи сохранены в $LOGFILE."

exit 0
