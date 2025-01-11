Скрипт настраивает базовую безопасность VPS. Вы будете выбирать, какие операции провести, и будете вводить необходимые значения. Скрипт запускается непосредственно на VPS, который нужно настроить.

Для запуска скрипта выполняем эту команду:
         
         wget https://raw.githubusercontent.com/jkbjkflkp/bom1/refs/heads/main/secure_vps_menu.sh -O secure_vps_menu.sh
         chmod +x secure_vps_menu.sh
         sed -i 's/\r//' ./secure_vps_menu.sh
         sudo ./secure_vps_menu.sh

для версии 0.2

         wget https://raw.githubusercontent.com/jkbjkflkp/bom1/refs/heads/main/secure_vps_menu%20v.0.2.sh -O secure_vps_menu%20v.0.2.sh
     chmod +x secure_vps_menu%20v.0.2.sh
     sed -i 's/\r//' ./secure_vps_menu%20v.0.2.sh
     sudo ./secure_vps_menu%20v.0.2.sh
