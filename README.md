Secure VPS Setup Script

Описание
Этот скрипт предназначен для автоматизации ряда задач по настройке безопасности на вашем VPS (Виртуальном Приватном Сервере). Он обеспечивает упрощенное управление пользователями, настройку SSH, защиту через Fail2Ban и UFW, а также поддерживает дополнительные утилиты и сервисы.

Преимущества использования скрипта:

Автоматизация: Скрипт автоматизирует рутинные задачи настройки безопасности, сокращая время и усилия на конфигурацию.
Легкость использования: Все настройки безопасности могут быть применены через удобное меню с выбором опций.

Гибкость: Поддержка как локального, так и удаленного управления через SSH.
Логирование: Все действия скрипта записываются в лог-файл для последующего аудита.

Безопасность: Улучшение безопасности сервера благодаря правильной настройке компонентов и защитных механизмов.


Как начать использовать:
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

Для запуска скрипта BBR v.0.1.

     wget https://raw.githubusercontent.com/jkbjkflkp/bom1/refs/heads/main/BBR%20v.0.1.sh -O BBR%20v.0.1.sh
     chmod +x BBR%20v.0.1.sh
     sed -i 's/\r//' ./BBR%20v.0.1.sh
     sudo ./BBR%20v.0.1.sh
