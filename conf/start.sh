#!/bin/bash
certname='srvtest'
stop_requested=false
trap "stop_requested=true" SIGTERM SIGINT

wait_signal() {
    while ! $stop_requested; do
        sleep 1;

        cryptsrv=`pidof cryptsrv`
        if [ -z "$cryptsrv" ]
        then
            stop_requested=true
            echo "Error cryptsrv not required stopping"
        fi

        php=`pidof php`
        if [ -z "$php" ]
        then
            stop_requested=true
            echo "Error php not required stopping"
        fi
    done
}

wait_exit() {
    while pidof $1; do
        sleep 1
        echo "Wait services"
    done
}

/sbin/init
# Ждем инициализации на всякий
sleep 5 && \

# Запускаем сервис криптопро - криптопровайдер
/etc/init.d/cprocsp start && \
cd /root && \

# Доустановка пакета не проходит при былде
alien -kci cprocsp-pki-2.0.0-amd64-cades.rpm && \

# Создание хранилища текущего пользователя
/opt/cprocsp/sbin/amd64/cpconfig -hardware reader -add HDIMAGE store && \

# Скачивание корневых и УЦ сертификатов
#php5.6 getRootAndCACerts.php && \

# Установка коневых сертификатов
/opt/cprocsp/bin/amd64/certmgr -inst -store uMy -cont '\\.\HDIMAGE\srvtest' -provtype 75
/opt/cprocsp/bin/amd64/certmgr -export -cert -dn "CN=${certname}" -dest "/etc/nginx/${certname}.cer" || exit 1
openssl x509 -inform DER -in "/etc/nginx/${certname}.cer" -out "/etc/nginx/${certname}.pem" || exit 1
openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/${certname}RSA.key -nodes -out /etc/nginx/srvtestRSA.pem -subj '/CN=${certname}RSA/C=RU' || exit 1
openssl rsa -in /etc/nginx/srvtestRSA.key -out /etc/nginx/${certname}RSA.key

# Загрузка файла конфигурации:
wget --no-check-certificate "https://raw.githubusercontent.com/fullincome/scripts/master/nginx-gost/nginx.conf" || exit 1

# Установка конфигурации nginx:
sed -r "s/srvtest/${certname}/g" nginx.conf > nginx_tmp.conf
rm nginx.conf
mv ./nginx_tmp.conf /etc/nginx/nginx.conf || exit 1

# Ждём SIGTERM или SIGINT
wait_signal

echo "Stoping services"

# Запрашиваем остановку запущенных процессов

if pidof "cryptsrv" > /dev/null
then
    /etc/init.d/cprocsp stop
fi

if pidof "php" > /dev/null
then
    kill $(pidof php)
fi

# Ждём завершения процессов по их названию
wait_exit "cryptsrv"
