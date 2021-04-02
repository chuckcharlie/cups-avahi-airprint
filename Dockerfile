FROM alpine:latest

# Install the packages we need. Avahi will be included
RUN echo "http://nl.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories &&\
	apk add --update cups \
	cups-libs \
	cups-pdf \
	cups-client \
	cups-filters \
	cups-dev \
	gutenprint \
	gutenprint-libs \
	gutenprint-doc \
	gutenprint-cups \
	ghostscript \
	hplip \
	avahi \
	inotify-tools \
	python3 \
	python3-dev \
	py3-pip \
	build-base \
	wget \
	rsync \
	&& pip3 --no-cache-dir install --upgrade pip \
	&& pip3 install pycups \
	&& rm -rf /var/cache/apk/*

# This will use port 631
EXPOSE 631

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
