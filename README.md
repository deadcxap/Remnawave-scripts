# server-scripts
ssh.sh - данный скрипт для первичной настройки VPS сервера: меняет порт SSH, устанавливает доступ "по ключам", предварительно спросив ключ, добавляет новый порт в UFW и закрывает 22, если было выбрано в меню. Также закрывает доступ по паролям и несколько минимально необходимых настроек. В конце пишет лог работы и текущие изменения - выбранный порт и статус файервола.
Перед запуском не забудьте сделать `chmod +X ssh.sh`
Запускать скрипт: `bash ssh.sh`
ВАЖНО: SSH ключ у вас уже должен быть сгенерирован в Windows заранее любым способом.

remnanode_analyzer.sh
![image](https://github.com/user-attachments/assets/24c9195d-dc0f-42aa-9036-a4567b3d2669)

remna-update-manager.sh
![image](https://github.com/user-attachments/assets/200a05dc-c228-4592-b8bc-af03208548b9)

Remnawave_backup.sh:
останавливает контейнеры, затем делает бэкап volumes БД и Редис, содержимого папки /opt/remnawave и затем запускает контейнеры
![image](https://github.com/user-attachments/assets/8f0c7183-56ab-4337-afad-0a785f1daae7)
