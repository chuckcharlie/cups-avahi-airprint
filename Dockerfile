FROM alpine:3.18

# Upgrade Alpine, install stable Alpine packages, install Edge Alpine packages, install pycups
RUN	apk upgrade --no-cache && \
	apk add --no-cache cups \
	cups-libs \
	cups-client \
	cups-filters \
	cups-dev \
	ghostscript \
	brlaser \
	avahi \
	inotify-tools \
	python3 \
	python3-dev \
	py3-pip \
	build-base \
	wget \
	rsync && \
	apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
	hplip \
	gutenprint \
	gutenprint-libs \
	gutenprint-doc \
	gutenprint-cups && \
	pip3 install --no-cache-dir -r requirements.txt

# This will use port 631
EXPOSE 631/tcp
EXPOSE 5353/udp

# We want a mount for these
VOLUME /config
VOLUME /services

# Add scripts
ADD root /
RUN chmod +x /root/*

#Run Script
CMD ["/root/run_cups.sh"]

# Baked-in config file changes
RUN sed -i 's/Listen localhost:631/Listen 0.0.0.0:631/' /etc/cups/cupsd.conf && \
	sed -i 's/Browsing Off/Browsing On/' /etc/cups/cupsd.conf && \
	sed -i 's/<Location \/>/<Location \/>\n  Allow All/' /etc/cups/cupsd.conf && \
	sed -i 's/<Location \/admin>/<Location \/admin>\n  Allow All\n  Require user @SYSTEM/' /etc/cups/cupsd.conf && \
	sed -i 's/<Location \/admin\/conf>/<Location \/admin\/conf>\n  Allow All/' /etc/cups/cupsd.conf && \
	sed -i 's/.*enable\-dbus=.*/enable\-dbus\=no/' /etc/avahi/avahi-daemon.conf && \
	echo "ServerAlias *" >> /etc/cups/cupsd.conf && \
	echo "DefaultEncryption Never" >> /etc/cups/cupsd.conf
