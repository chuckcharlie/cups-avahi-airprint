#!/bin/sh
set -e
set -x

if [ $(grep -ci $CUPSADMIN /etc/shadow) -eq 0 ]; then
    useradd -r -G lpadmin -M $CUPSADMIN 
fi
echo $CUPSADMIN:$CUPSPASSWORD | chpasswd

mkdir -p /config/ppd
mkdir -p /services
rm -rf /etc/cups/ppd
ln -s /config/ppd /etc/cups
if [ ! -f /config/printers.conf ]; then
    touch /config/printers.conf
fi
cp /config/printers.conf /etc/cups/printers.conf

/root/printer-update.sh &
exec /usr/sbin/cupsd -f
