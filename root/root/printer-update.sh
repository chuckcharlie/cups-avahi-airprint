#!/bin/sh
/usr/bin/inotifywait -m -e close_write,moved_to,create /etc/cups | 
while read -r directory events filename; do
	if [ "$filename" = "printers.conf" ]; then
		cp /etc/cups/printers.conf /config/printers.conf
	fi
	if [ "$filename" = "cupsd.conf" ]; then
		cp /etc/cups/cupsd.conf /config/cupsd.conf
	fi
done
