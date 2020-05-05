FROM ubuntu:bionic

ENV CANON_DRIVER_URL='http://gdlp01.c-wss.com/gds/8/0100007658/08/linux-UFRII-drv-v370-uken-05.tar.gz'
ENV CUPS=1.3

# Add repos
RUN echo 'deb http://us.archive.ubuntu.com/ubuntu/ bionic multiverse' >> /etc/apt/sources.list.d/multiverse.list && \
	echo 'deb-src http://us.archive.ubuntu.com/ubuntu/ bionic multiverse' >> /etc/apt/sources.list.d/multiverse.list && \
	echo 'deb http://us.archive.ubuntu.com/ubuntu/ bionic-updates multiverse' >> /etc/apt/sources.list.d/multiverse.list && \
	echo 'deb-src http://us.archive.ubuntu.com/ubuntu/ bionic-updates multiverse' >> /etc/apt/sources.list.d/multiverse.list && \
	echo 'deb http://archive.ubuntu.com/ubuntu/ bionic-security multiverse' >> /etc/apt/sources.list.d/multiverse.list && \
	echo 'deb-src http://archive.ubuntu.com/ubuntu/ bionic-security multiverse' >> /etc/apt/sources.list.d/multiverse.list

# Install the packages we need. Avahi will be included
RUN apt-get update && apt-get install -y \
	brother-lpr-drivers-extra brother-cups-wrapper-extra \
	cups \
	cups-pdf \
	inotify-tools \
	libglade2-0 \
  libpango1.0-0 \
  libpng16-16 \
	python-cups \
	curl \
&& rm -rf /var/lib/apt/lists/*

# Install UFRII drivers
RUN curl $CANON_DRIVER_URL | tar xz && \
    dpkg -i *-UFRII-*/64-bit_Driver/Debian/*common*.deb && \
    dpkg -i *-UFRII-*/64-bit_Driver/Debian/*ufr2*.deb && \
    dpkg -i *-UFRII-*/64-bit_Driver/Debian/*utility*.deb && \
    rm -rf *-UFRII-*

# This will use port 631
EXPOSE 631

# We want a mount for these
VOLUME /config
VOLUME /services

# Add scripts
ADD root /
RUN chmod +x /root/*
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