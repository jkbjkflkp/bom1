#!/bin/bash

# Function to check for errors
check_for_errors() {
    if [ $? -ne 0 ]; then
        echo "Error occurred. Exiting."
        exit 1
    fi
}

# Open the file with nano and edit
FILE="/etc/ufw/before.rules"

# Ensure the file exists
if [ ! -f "$FILE" ]; then
    echo "File $FILE does not exist. Exiting."
    exit 1
fi

# Backup the file before making changes
cp "$FILE" "$FILE.bak"
check_for_errors

echo "Adding new line to the INPUT block."
sed -i '/# ok icmp codes for INPUT/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' "$FILE"
check_for_errors

# Verify the changes
grep "-A ufw-before-input -p icmp --icmp-type source-quench -j DROP" "$FILE" >/dev/null
if [ $? -ne 0 ]; then
    echo "Failed to add the new line. Exiting."
    exit 1
fi

echo "Replacing ACCEPT with DROP in relevant blocks."
sed -i '/# ok icmp codes for INPUT/,/# ok icmp code for FORWARD/ s/ACCEPT/DROP/' "$FILE"
check_for_errors

# Verify the changes
grep "ACCEPT" "$FILE" | grep -E "# ok icmp codes for INPUT|# ok icmp code for FORWARD" >/dev/null
if [ $? -eq 0 ]; then
    echo "Failed to replace ACCEPT with DROP. Exiting."
    exit 1
fi

# Ensure UFW is installed and active (specific for Ubuntu 24)
if ! command -v ufw &>/dev/null; then
    echo "UFW is not installed. Installing..."
    apt update && apt install -y ufw
    check_for_errors
fi

if ! systemctl is-active --quiet ufw; then
    echo "UFW is not active. Enabling..."
    ufw enable
    check_for_errors
fi

# Restart UFW
echo "Restarting UFW."
ufw disable && ufw enable
check_for_errors

echo "Script executed successfully for Ubuntu 24."
