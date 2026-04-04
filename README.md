# chuckcharlie/cups-avahi-airprint

Fork from [quadportnick/docker-cups-airprint](https://github.com/quadportnick/docker-cups-airprint)

### Supports ARM64 and AMD64.
Use the *latest* or *version#* tags to auto choose the right architecture.

This Alpine-based Docker image runs a CUPS instance that is meant as an AirPrint relay for printers that are already on the network but not AirPrint capable.

## How it works

CUPS registers shared printers directly with Avahi via D-Bus for mDNS/DNS-SD advertisement. When you add a printer in CUPS and mark it as shared, it automatically becomes discoverable by iPhones, iPads, and Macs on your network -- no extra configuration needed.

## Changes in v2.0

- **Native DNS-SD registration**: CUPS now registers printers with Avahi directly over D-Bus, replacing the previous `airprint-generate.py` script that manually created Avahi service files. This fixes an issue where iOS devices would show duplicate printer entries due to a mismatch between the mDNS service name and the CUPS IPP response.
- **Removed `/services` volume**: No longer needed since Avahi service files are no longer generated externally.

## Configuration

### Volumes:
* `/config`: where the persistent printer configs will be stored

### Variables:
* `CUPSADMIN`: the CUPS admin user you want created - default is CUPSADMIN if unspecified
* `CUPSPASSWORD`: the password for the CUPS admin user - default is the same value as `CUPSADMIN` if unspecified
* `AVAHI_HOSTNAME`: the mDNS hostname Avahi will advertise - default is `cups-airprint`. Set this to a unique name if you have multiple instances, or if the default conflicts with your host's mDNS daemon (common on NAS devices like UGreen, Synology, etc.)

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
```yaml
services:
  cups:
    image: chuckcharlie/cups-avahi-airprint:latest
    container_name: cups
    network_mode: host
    volumes:
      - ./config:/config
    environment:
      CUPSADMIN: "<YourAdminUsername>"
      CUPSPASSWORD: "<YourPassword>"
    restart: unless-stopped
```

## Add and set up printer:
* CUPS will be configurable at http://[host ip]:631 using the CUPSADMIN/CUPSPASSWORD.
* Make sure you select `Share This Printer` when configuring the printer in CUPS.
