#!/bin/bash

#Версия скрипта
ver=0.2.1

#  Проверяем наличие каталога для логов, создаем если отсутсвует

if ! [ -d /var/log/sql_backup_universal ]
then
     mkdir /var/log/sql_backup_universal
fi

#######################################   ФУНКЦИИ   ##########################################

#  функция вывода подсказки
print_help()
{
cat << EOF

VERSION 0.2.1

Options:
      --help               print this help message
      --version            print script version
      --conf               helps to choose config file which contain all needed parameters

      Example:

      $0 --conf /full/path/to/config/file.conf

NOTICE:
       If you don't type the full path to configurton file,
       script'll try to find this file in a current directory.

NOTICE:
       Configuration file should include parameters like these

       #Хостнейм сервера где находится бэкапируемая база
       remote_host=examlpe.remote.host

       #Ответственный за выполнение бэкапа(Фамилия)
       admin_second_name=example_admin_second_name

       #Порт ssh для подключения к серверу с бекапируемой базой
       #по умолчанию порт 22
       port_ssh=22

       #Пользователь от имени которого выполняются команды на удаленном сервере
       #если ничего не указано подключение от имени пользователя backup
       system_backup_user=example_system_backup_user

       #Выбор утилиты для бэкапа базы(xtrabackup, mysqldump, pg_dump)
       type_backup=example_type

       #Выбор схем для бэкапа(для mysqldump и pg_dump)
       #бэкап всех баз если в schema_names ничего не указано!!!
       #для PostgreSQL указываем одну схему, для mysql можно указать
       #несколько схем в круглых скобках через пробел
       schema_names=(example_schema1 example_schema2 example_schema3)

       #Пользователь для подключения к базе sql
       backup_user=example_user

       #Пароль пользователя для подключения к базе sql
       backup_password=example_password

       #Локальная директория для хранения бэкапов
       #в данной директория будет создана директория с именем сервера БД и
       #вложенный каталог с датой и временем бэкапа
       #по умолчанию /opt/backup-other/sql
       sql_backup_stor=/some/example/directory

       #Описание(если требуется)
       #дополнительная информация по бэкапу
       description=some_info

       #Атрибут отправки лога(по умолчанию yes)
       send_log_file=yes

       #email для отправки результата выполнения скрипта
       adm_email=example@domen.ru

       ###Запись результата выполнения скрипта в базу

       #Атрибут записи результата выполнения скрипта в базу(yes/no)
       #по умолчанию yes
       write_resume=yes

       #Хостнейм sql сервера куда пишется результат выполнения скрипта
       hostname_sql_resume=example_mysql_server

       #Порт для подключения к базе MySQL куда пишем результаты
       #по умолчанию 3306
       port_sql_resume=3306

       #Имя схемы куда пишем
       #таблица results
       schema_name_sql_resume=example_schema_name

       #Пользователь для подключения к sql базе результатов
       sql_resume_user=example_user

       #Пароль пользователя для подключения к sql базе результатов
       sql_resume_password=example_password

NOTICE:
                                    PostgreSQL

       Для подключения к базе PostgreSQL используется пользователь postgres,
       пароль пользователя postgres задан в ОС. Подключение производится без пароля
       по ssh ключю.

NOTICE:
       Log file
       /var/log/sql_backup_universal/sql_backup_remote_host.log

EOF
}

#  Функция вывода даты и времени(вызыввется в начале и в конце работы скрипта)
print_date()
{
date_time=`date +%F" "%H:%M:%S`
echo "********************************  $date_time  **************************************"
echo "********************************  $date_time  **************************************" >> $LOG
}

#  Функция проверки доступности удаленного хоста
check_host()
{
echo
echo
echo "* * * * * Checking for host alive * * * * *"
echo "* * * * * Checking for host alive * * * * *" >> $LOG
echo
good()
{
echo "* * * * * $remote_host : checked! * * * * *"
echo "* * * * * $remote_host : checked! * * * * *" >> $LOG
}
notgood()
{
comment=$(echo "Host $remote_host seems to be down or user $system_backup_user does NOT EXIST.")
echo "* * * * * WARNING!!! Host $remote_host seems to be down or user $system_backup_user does NOT EXIST. Please check it out!!! * * * * *"
echo "* * * * * WARNING!!! Host $remote_host seems to be down or user $system_backup_user does NOT EXIST. Please check it out!!! * * * * *" >> $LOG
echo "* * * * * Script $0 was stopped! * * * * *"
echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
echo
echo >> $LOG
print_date
status=fail
send_log
send_resume_to_sql
exit
}
ssh -p$port_ssh -q -o "BatchMode=yes" $system_backup_user@$remote_host "echo 2>&1" && good || notgood
sleep 1
}

#  Функция записи результата выполнения скрипта в базу mysql на удаленный сервер
send_resume_to_sql()
{
stop_time=`date +%F" "%H:%M:%S`
if [[ $write_resume == no ]]
then echo
else
    if [[ $status == ok ]]
    then
        mysql -u$sql_resume_user -p$sql_resume_password -h$hostname_sql_resume -P$port_sql_resume -e "INSERT INTO $schema_name_sql_resume.results (hostname, description, schema_name, status, backupserver, path, size, start_time, stop_time, admin_name, comment) VALUES ('$remote_host', '$description', '${schema_names[*]}', '$status', '$backupserver', '$dir_local', '$size', '$start_time', '$stop_time', '$admin_second_name', '$comment');"

    else
        mysql -u$sql_resume_user -p$sql_resume_password -h$hostname_sql_resume -P$port_sql_resume -e "INSERT INTO $schema_name_sql_resume.results (hostname, description, schema_name, status, backupserver, start_time, stop_time, admin_name, comment) VALUES ('$remote_host', '$description', '${schema_names[*]}', '$status', '$backupserver', '$start_time', '$stop_time', '$admin_second_name', '$comment');"
    fi
fi
}

#  Функция проверки наличия достаточного обьема свободного дискового пространства под временные файлы на удаленном сервере(MySQL)
check_space_mysql()
{
export avail_space=$(ssh $system_backup_user@$remote_host sudo /bin/df /opt | awk '{print $4}' | awk 'NR==2')
export used_space=$(ssh $system_backup_user@$remote_host sudo /usr/bin/du -s /var/lib/mysql | awk '{print $1}')
let "max_space_xtrabackup=$used_space * 9 / 5"
let "max_space_mysqldump=$used_space"
if [[ $type_backup == xtrabackup ]]
then
    if [ "$avail_space" -lt "$max_space_xtrabackup" ]
    then
        comment=$(echo "Not enough space on remote server.")
        echo "* * * * * Not enough space on remote server!!! * * * * *"
        echo "* * * * * Not enough space on remote server!!! * * * * *" >> $LOG
        echo "* * * * * Script $0 was stopped! * * * * *"
        echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
        print_date
        status=fail
        send_log
        send_resume_to_sql
        exit
    fi
else
    if [ "$avail_space" -lt "$max_space_mysqldump" ]
    then
        comment=$(echo "Not enough space on remote server.")
        echo "* * * * * Not enough space on remote server!!! * * * * *"
        echo "* * * * * Not enough space on remote server!!! * * * * *" >> $LOG
        echo "* * * * * Script $0 was stopped! * * * * *"
        echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
        print_date
        status=fail
        send_log
        send_resume_to_sql
        exit
    fi
fi
}

#  Функция проверки наличия достаточного обьема свободного дискового пространства под временные файлы на удаленном сервере(PostgreSQL)
check_space_pgsql()
{
export avail_space=$(ssh $system_backup_user@$remote_host sudo /bin/df /opt | awk '{print $4}' | awk 'NR==2')
export used_space=$(ssh $system_backup_user@$remote_host sudo /usr/bin/du -s /var/lib/pgsql | awk '{print $1}')
let "max_space_pg_dump=$used_space * 2 / 3"
if [ "$avail_space" -lt "$max_space_pg_dump" ]
then
    comment=$(echo "Not enough space on remote server.")
    echo "* * * * * Not enough space on remote server!!! * * * * *"
    echo "* * * * * Not enough space on remote server!!! * * * * *" >> $LOG
    echo "* * * * * Script $0 was stopped! * * * * *"
    echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
    print_date
    status=fail
    send_log
    send_resume_to_sql
    exit
fi
}

#  Функция выполняющая проверку атрибута отправки лога, а так же отправку лога в случае если значение атрибута YES
send_log()
{
if [[ $send_log_file == no ]]
then echo
else
    if [[ $status == fail ]]
    then
        cat /var/log/sql_backup_universal/sql_backup_$remote_host.log | sed -e :a -e '$q;N;17,$D;ba' | mail -s "Backup database $remote_host FAIL!" $adm_email
    else
         if [[ $type_backup == xtrabackup ]]
         then
              cat /var/log/sql_backup_universal/sql_backup_$remote_host.log | sed -e :a -e '$q;N;23,$D;ba' | mail -s "Backup database $remote_host OK!" $adm_email
         else
             cat /var/log/sql_backup_universal/sql_backup_$remote_host.log | sed -e :a -e '$q;N;22,$D;ba' | mail -s "Backup database $remote_host OK!" $adm_email
         fi
    fi
fi
}

#  Функция выполнения бэкапа с помощью Percona Xtrabackup
xtrabackup_func()
{
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/rm -rf /opt/backup_sql_2*
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/mkdir -p $dir_remote
ssh $system_backup_user@$remote_host -p$port_ssh sudo /usr/bin/innobackupex --user=$backup_user --password=$backup_password $dir_remote
export dir_temp=$(ssh $system_backup_user@$remote_host -p$port_ssh "sudo /bin/ls /$dir_remote")
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "+ + + + + + + + + + + + + + + + + + + + SUCCESS + + + + + + + + + + + + + + + + + + + + + + + + +"
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "* * * * * innobackupex: completed OK! * * * * *" >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh sudo /usr/bin/innobackupex --apply-log $dir_remote/$dir_temp
echo "* * * * * innobackupex: applying log completed OK! * * * * *" >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/chown -R $system_backup_user.$system_backup_user $dir_remote
ssh $system_backup_user@$remote_host -p$port_ssh " cd $dir_remote/$dir_temp ; tar -czf $dir_remote/$remote_host_$date1.tar.gz * "
rsync -a --port=$port_ssh $system_backup_user@$remote_host:$dir_remote/$remote_host_$date1.tar.gz $dir_local
echo >> $LOG
echo "Checksum:" >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh md5sum $dir_remote/$remote_host_$date1.tar.gz | cut -f1 -d/ >> $LOG
md5sum $dir_local/$remote_host_$date1.tar.gz | cut -f1 -d/ >> $LOG
echo "Archive size:" >> $LOG
size=$(du -sh $dir_local/$remote_host_$date1.tar.gz | awk '{print $1}')
du -sh $dir_local/$remote_host_$date1.tar.gz >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/rm -rf /opt/backup_sql_2*
}

#  Функция выполнения бэкапа с помощью mysqldump
mysqldump_func()
{
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/rm -rf /opt/backup_sql_2*
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/mkdir -p $dir_remote
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/chown -R $system_backup_user.$system_backup_user $dir_remote
ssh $system_backup_user@$remote_host -p$port_ssh "sudo /usr/bin/mysqldump -u$backup_user -p$backup_password  -B ${schema_names[*]} > $dir_remote/$date1.dmp "
echo "* * * * * Dump file was successfully created! * * * * *"
echo "* * * * * Dump file was successfully created! * * * * *" >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh " cd $dir_remote ; tar -czf $dir_remote/$remote_host_$date1.tar.gz $date1.dmp "
rsync -a --port=$port_ssh $system_backup_user@$remote_host:$dir_remote/$remote_host_$date1.tar.gz $dir_local
echo >> $LOG
echo "Checksum:" >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh md5sum $dir_remote/$remote_host_$date1.tar.gz | cut -f1 -d/ >> $LOG
md5sum $dir_local/$remote_host_$date1.tar.gz | cut -f1 -d/ >> $LOG
echo "Archive size:" >> $LOG
size=$(du -sh $dir_local/$remote_host_$date1.tar.gz | awk '{print $1}')
du -sh $dir_local/$remote_host_$date1.tar.gz >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/rm -rf /opt/backup_sql_2*
}

#  Функция выполнения бэкапа с помощью pg_dump
pg_dump_func()
{
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/rm -rf /opt/backup_sql_2*
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/mkdir -p $dir_remote
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/chown -R postgres.postgres $dir_remote
ssh postgres@$remote_host -p$port_ssh "pg_dump -Fc -b -v -f $dir_remote/$date1.backup ${schema_names[*]} ;"
echo "* * * * * Backup file was successfully created! * * * * *"
echo "* * * * * Backup file was successfully created! * * * * *" >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/chown -R $system_backup_user.$system_backup_user $dir_remote
ssh $system_backup_user@$remote_host -p$port_ssh " cd $dir_remote ; tar -czf $dir_remote/$remote_host_$date1.tar.gz $date1.backup "
rsync -a --port=$port_ssh $system_backup_user@$remote_host:$dir_remote/$remote_host_$date1.tar.gz $dir_local
echo >> $LOG
echo "Checksum:" >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh md5sum $dir_remote/$remote_host_$date1.tar.gz | cut -f1 -d/ >> $LOG
md5sum $dir_local/$remote_host_$date1.tar.gz | cut -f1 -d/ >> $LOG
echo "Archive size:" >> $LOG
size=$(du -sh $dir_local/$remote_host_$date1.tar.gz | awk '{print $1}')
du -sh $dir_local/$remote_host_$date1.tar.gz >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/rm -rf /opt/backup_sql_2*
}

#  Функция выполнения бэкапа с помощью pg_dumpall
pg_dumpall_func()
{
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/rm -rf /opt/backup_sql_2*
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/mkdir -p $dir_remote
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/chown -R postgres.postgres $dir_remote
ssh postgres@$remote_host -p$port_ssh "pg_dumpall > $dir_remote/$date1.sql ;"
echo "* * * * * Backup file was successfully created! * * * * *"
echo "* * * * * Backup file was successfully created! * * * * *" >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/chown -R $system_backup_user.$system_backup_user $dir_remote
ssh $system_backup_user@$remote_host -p$port_ssh " cd $dir_remote ; tar -czf $dir_remote/$remote_host_$date1.tar.gz $date1.sql "
rsync -a --port=$port_ssh $system_backup_user@$remote_host:$dir_remote/$remote_host_$date1.tar.gz $dir_local
echo >> $LOG
echo "Checksum:" >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh md5sum $dir_remote/$remote_host_$date1.tar.gz | cut -f1 -d/ >> $LOG
md5sum $dir_local/$remote_host_$date1.tar.gz | cut -f1 -d/ >> $LOG
echo "Archive size:" >> $LOG
size=$(du -sh $dir_local/$remote_host_$date1.tar.gz | awk '{print $1}')
du -sh $dir_local/$remote_host_$date1.tar.gz >> $LOG
ssh $system_backup_user@$remote_host -p$port_ssh sudo /bin/rm -rf /opt/backup_sql_2*
}

#########################   КОНЕЦ  ОПИСАНИЯ  ФУНКЦИЙ   ###############################

if [ $# -eq 0 ]; then
echo
echo "$0 --help for more information" 1>&2
echo
exit
fi

set -e
OPTS=`getopt -n $0 -o UR:B: --long help::,version::,conf: -- $@`
eval set -- "$OPTS"

while true; do
case $1 in
   --conf)
   case "$2" in
      *.conf) conf_file=$2; break ;;
          "")echo
           echo "Option $1 has no argument"; exit
           echo ;;
           *)  echo
           echo "Option $1 has invalid argument \`$2'"
           echo "Please enter '$0 --help' for more information"
           echo
           exit;;
    esac ;;
   --help)
   print_help
   exit
   ;;
   --version)
   echo
   echo "VERSION $ver"
   echo
   exit
   ;;
   *)
   echo "Invalid option: $OPTS!!!"
   exit
   ;;
esac
done

if [[ -e $conf_file ]]
then echo
     echo "* * * * * Configuration file EXISTS! * * * * *"
     echo

else
    echo
    echo "* * * * * Configuration file does NOT EXIST! * * * * *"
    echo
    exit
fi

#  подключаем выбранный конфигурационный файл, определяем значения параметров по умолчанию
#  если в конфигурационном файле значения не заданы
source $conf_file

LOG="/var/log/sql_backup_universal/sql_backup_$remote_host.log"
print_date
start_time=`date +%F" "%H:%M:%S`

if [ -z $port_ssh ]
then
    port_ssh=22
fi

if [ -z $system_backup_user ]
then
    system_backup_user=backup
fi

if [ -z $schema_names ]
then
    schema_names=--all-databases
fi

if [ -z $sql_backup_stor ]
then
   sql_backup_stor=/opt/backup-other/sql
   mkdir -p $sql_backup_stor
fi

if [ -z $backup_user ]
then
    if [ $type_backup != pg_dump ]
    then
    echo "Please enter sql user in $conf_file!!!"
    echo "Please enter sql user in $conf_file!!!" >> $LOG
    echo "* * * * * Script $0 was stopped! * * * * *"
    echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
    print_date
    exit
    fi
fi

if [ -z $backup_password ]
then
    if [ $type_backup != pg_dump ]
    then
    echo "Please enter sql password in $conf_file!!!"
    echo "Please enter sql password in $conf_file!!!" >> $LOG
    echo "* * * * * Script $0 was stopped! * * * * *"
    echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
    print_date
    exit
    fi
fi

if [ -z $send_log_file ]
then
    send_log_file=yes
fi

if [ -z $admin_second_name ]
then
    echo "Please enter admin second name in $conf_file!!!"
    echo "Please enter admin second name in $conf_file!!!" >> $LOG
    echo "* * * * * Script $0 was stopped! * * * * *"
    echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
    print_date
    exit
fi

if [ -z $adm_email ]
then
    send_log_file=no
fi

if [ -z $write_resume ]
then
    write_resume=yes
fi

#  Проверяем наличие необходимых переменных, в случае выбора записи результатов выполнения скрипта в базу MySQL
if [ $write_resume == yes ]
then
    if [ -z $hostname_sql_resume ]
    then
        echo "Please enter hostname_sql_resume in $conf_file!!!"
        echo "Please enter hostname_sql_resume in $conf_file!!!" >> $LOG
        echo "* * * * * Script $0 was stopped! * * * * *"
        echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
        print_date
        exit
    else
#  Проверяем доступность сервера c базой MySQL для записи результатов
        packets_count=$(ping -c 2 $hostname_sql_resume | grep 'received' | awk -F',' '{ print $2 }' | awk '{ print $1 }')

        if [ $packets_count -eq 2 ]
        then
            if [ -z $port_sql_resume ]
            then
                port_sql_resume=3306
            else
                if [ -z $schema_name_sql_resume ]
                then
                    echo "Please enter schema_name_sql_resume in $conf_file!!!"
                    echo "Please enter schema_name_sql_resume in $conf_file!!!" >> $LOG
                    echo "* * * * * Script $0 was stopped! * * * * *"
                    echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
                    print_date
                    exit
                else
                    if [ -z $sql_resume_user ]
                    then
                        echo "Please enter sql_resume_user in $conf_file!!!"
                        echo "Please enter sql_resume_user in $conf_file!!!"
                        echo "* * * * * Script $0 was stopped! * * * * *"
                        echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
                        print_date
                        exit
                    else
                        if [ -z $sql_resume_password ]
                        then
                            echo "Please enter sql_resume_user in $conf_file!!!"
                            echo "Please enter sql_resume_user in $conf_file!!!"
                            echo "* * * * * Script $0 was stopped! * * * * *"
                            echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
                            print_date
                            exit
                        fi
                    fi
                fi
            fi
        else
            echo "* * * * * WARNING!!! Host $hostname_sql_resume seems to be down. Please check it out!!! * * * * *"
            echo "* * * * * WARNING!!! Host $hostname_sql_resume seems to be down. Please check it out!!! * * * * *" >> $LOG
            echo "* * * * * Script $0 was stopped! * * * * *"
            echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
            print_date
            exit
        fi
    fi
fi

#  Выводим исходные даннные и объявляем перменные
echo "Basic data"
echo "Description : $description"
echo "Remote host : $remote_host"
echo "System backup user : $system_backup_user"
echo "Backup type : $type_backup"
echo "Schema names(mysqldump,pg_dump) : ${schema_names[*]}"
echo "Sql backup local directory : $sql_backup_stor"
echo "Send log file : $send_log_file"
echo "Admin email : $adm_email"
echo "Log file : $LOG"
echo
echo "Basic data" >> $LOG
echo "Description : $description" >> $LOG
echo "Remote host : $remote_host" >> $LOG
echo "System backup user : $system_backup_user" >> $LOG
echo "Backup type : $type_backup" >> $LOG
echo "Schema names(mysqldump,pg_dump) : ${schema_names[*]}" >> $LOG
echo "Sql backup local directory : $sql_backup_stor" >> $LOG
echo "Admin second name : $admin_second_name" >> $LOG
echo "Admin email : $adm_email" >> $LOG
echo >> $LOG

date1=$(date +%F-%H-%M)
dir_remote=/opt/backup_sql_$date1
dir_local=$sql_backup_stor/$remote_host/$date1
mkdir -p $dir_local
status=ok
backupserver=$(hostname)

#  Проверяем корректность параметра type_backup и запускаем функцию соответвующую данному параметру
if [[ $type_backup == xtrabackup ]]
then check_host
     check_space_mysql
     xtrabackup_func
     scp $system_backup_user@$remote_host:/etc/my.cnf $dir_local
else
     if [[ $type_backup == mysqldump ]]
     then check_host
          check_space_mysql
          mysqldump_func
          scp $system_backup_user@$remote_host:/etc/my.cnf $dir_local
     else
          if [[ $type_backup == pg_dump ]]
          then check_host
               check_space_pgsql
               scp postgres@$remote_host:/var/lib/pgsql/9.3/data/pg_hba.conf $dir_local
               scp postgres@$remote_host:/var/lib/pgsql/9.3/data/postgresql.conf $dir_local
               if [[ $schema_names == --all-databases  ]]
               then
                    pg_dumpall_func
               else
                    pg_dump_func
               fi
          else
                    comment=$(echo "Wrong parameter backup type.")
                    echo
                    echo
                    echo "* * * * * Wrong parameter backup type! Please choose xtrabackup, mysqldump or pg_dump in the configuration file! * * * * *"
                    echo "* * * * * Script $0 was stopped! * * * * *"
                    echo >> $LOG
                    echo >> $LOG
                    echo "* * * * * Wrong parameter backup type! Please choose xtrabackup, mysqldump or pg_dump in the configuration file! * * * * *" >> $LOG
                    echo "* * * * * Script $0 was stopped! * * * * *" >> $LOG
                    status=fail
          fi
     fi
fi

print_date

send_log

send_resume_to_sql