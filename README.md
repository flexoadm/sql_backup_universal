# sql_backup_universal


Скрипт запускается с сервера бэкапов.
По-умолчанию бэкап выполняется от пользователя backup.
Данный пользователь должен существовать в системе на удаленном сервере.
Файл `backup` необходимо скопировать на удаленный сервер в /etc/sudoers.d, в нем прописаны необходимые права.
Так же необходимо добавить ssh ключ для доступа без пароля,выполнив команду на сервере бэкапов
```
ssh-copy-id backup@remote_server
```
Если пользователь для резервного копирования отличен от пользователя backup,
необходимо выполнить пункты 2-4 для данного пользователя.

## Сохранение логов в БД
Если результаты выполнения скрипта пишем в базу MySQL

1) На сервере бэкапов должен быть установлен клиент mysql

2) В базе данных, указанной в конфигурационом файле, должна существовать таблица results со следующими полями:

```
CREATE TABLE results (id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, hostname VARCHAR(30), \
description VARCHAR(30), schema_name VARCHAR(30),  status VARCHAR(5), backupserver VARCHAR(30), \
path VARCHAR(70), size VARCHAR(20), start_time DATETIME, stop_time DATETIME, admin_name VARCHAR(30), \
comment VARCHAR(100));
```


