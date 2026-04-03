# chuckcharlie/cups-avahi-airprint

Fork from [quadportnick/docker-cups-airprint](https://github.com/quadportnick/docker-cups-airprint)

### Now supports ARM64 and AMD64!
Use the *latest* or *version#* tags to auto choose the right architecture.

This Alpine-based Docker image runs a CUPS instance that is meant as an AirPrint relay for printers that are already on the network but not AirPrint capable. The other images out there never seemed to work right. I forked the original to use Alpine instead of Ubuntu and work on more host OS's.

## Configuration

### Volumes:
* `/config`: where the persistent printer configs will be stored

### Variables:
* `CUPSADMIN`: the CUPS admin user you want created - default is CUPSADMIN if unspecified
* `CUPSPASSWORD`: the password for the CUPS admin user - default is the same value as `CUPSADMIN` if unspecified

### Ports/Network:
* Must be run on host network. This is required to support multicasting which is needed for Airprint.

### Example run command:
```
docker run --name cups --restart unless-stopped  --net host\
  -v <your config dir>:/config \
  -e CUPSADMIN="<username>" \
  -e CUPSPASSWORD="<password>" \
  chuckcharlie/cups-avahi-airprint:latest
```

### Example docker compose config:
```
version: '3.5'
services:
  cups:
    image: chuckcharlie/cups-avahi-airprint:latest
    container_name: cups
    network_mode: host
    volumes:
      - </your/config/dir>:/config
    environment:
      CUPSADMIN: "<YourAdminUsername>"
      CUPSPASSWORD: "<YourPassword>"
    restart: unless-stopped
```

## Add and set up printer:
* CUPS will be configurable at http://[host ip]:631 using the CUPSADMIN/CUPSPASSWORD.
* Make sure you select `Share This Printer` when configuring the printer in CUPS.
* ***After configuring your printer, you need to close the web browser for at least 60 seconds. CUPS will not write the config files until it detects the connection is closed for as long as a minute.***

