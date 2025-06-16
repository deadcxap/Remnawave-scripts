# Remnawave-scripts


## remnanode_analyzer.sh

Подключается к контейнеру ноды, смотрит лог xray (последнюю 1000 записей), либо realtime

![image](https://github.com/user-attachments/assets/44b3e7c1-a577-4ead-a1c1-c169a7f4b12a)

## remna-update-manager.sh

Можно запланировать одноразовое обновление контейнеров по Московскому времени

Используется **at**. Если сейчас день, и задать 5:00, обновление будет завтра в 5:00

по московскому времени, не смотря на время сервера

![image](https://github.com/user-attachments/assets/0c33c20f-a120-456b-bdea-d7039c30e0be)


## Remnawave_backup.sh:
останавливает контейнеры, затем делает бэкап volumes БД и Редис, содержимого папки /opt/remnawave и затем запускает контейнеры

![image](https://github.com/user-attachments/assets/8f0c7183-56ab-4337-afad-0a785f1daae7)


