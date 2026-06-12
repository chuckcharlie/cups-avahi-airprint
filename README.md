# chuckcharlie/cups-avahi-airprint

Fork from [quadportnick/docker-cups-airprint](https://github.com/quadportnick/docker-cups-airprint)

### Supports ARM64 and AMD64.
Use the *latest* or *version#* tags to auto choose the right architecture.

This Alpine-based Docker image runs a CUPS instance that is meant as an AirPrint relay for printers that are already on the network but not AirPrint capable.

## How it works

CUPS registers shared printers directly with Avahi via D-Bus for mDNS/DNS-SD advertisement. When you add a printer in CUPS and mark it as shared, it automatically becomes discoverable by iPhones, iPads, and Macs on your network -- no extra configuration needed.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full version history.

> **⚠️ Upgrading from a pre-v2.0 version?** Remove `- /var/run/dbus:/var/run/dbus` from your compose file or `docker run` command if it's there. Pre-v2.0 this bind mount was harmless, but as of v2.0 the container runs its own `dbus-daemon`, which will write into that shared directory and clobber the host's system D-Bus socket — breaking host services like systemd, smartd, and management UIs until the container is removed. This is most visible on NAS platforms but affects any host.

## Configuration

### Volumes:
* `/config`: where the persistent printer configs are stored. This now also includes `/config/ssl`, where the self-signed TLS certificate and private key are kept so they stay stable across container restarts. The key is only used for the printer's own self-signed cert; keep this volume private.

### Variables:
* `CUPSADMIN`: the CUPS admin user you want created - defaults to `cupsadmin` if unspecified
* `CUPSPASSWORD`: the password for the CUPS admin user - default is the same value as `CUPSADMIN` if unspecified
* `AVAHI_HOSTNAME`: the mDNS hostname Avahi will advertise - default is `cups-airprint`. Set this to a unique name if you have multiple instances, or if the default conflicts with your host's mDNS daemon (common on NAS devices like UGreen, Synology, etc.)
* `TZ`: optional IANA timezone name (e.g. `Europe/Vienna`, `America/Los_Angeles`) used for log timestamps inside the container. Defaults to UTC if unset or invalid.

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

## Running on a NAS

First, make sure you've removed any `- /var/run/dbus:/var/run/dbus` bind mount from your compose (see the upgrade warning under **Changelog** above). That's the single most damaging misconfiguration on a NAS and will take down host services like the management UI.

NAS operating systems (TrueNAS Scale, Synology DSM, UGreen NAS OS, QNAP, etc.) typically run their own `avahi-daemon` on the host to advertise things like SMB shares, Time Machine, and Finder hostname visibility. When this container runs in host networking mode, both Avahi daemons share the host's network stack and can collide. Common symptoms:

* `bind() failed: Address in use` in the container logs, followed by `Failed to create IPv4 socket, proceeding in IPv6 only mode`. The host's Avahi already owns UDP 5353, so the container only gets IPv6 and most iOS devices never see the printer.
* A repeating `Host name conflict, retrying with <hostname>-NN` loop in the container logs. The container is trying to register the host's own hostname on mDNS.
* Printers work in the CUPS web UI but never show up in AirPrint on iOS/macOS.

Things to try, roughly in order of simplicity:

1. **Set `AVAHI_HOSTNAME`** to a unique value like `cups-airprint` (the default) or `mynas-print`. This avoids the hostname-conflict loop.
2. **Disable the host's mDNS/Bonjour service.** On TrueNAS Scale this is under **Network → Global Configuration**. On other NAS platforms look for a Bonjour, Avahi, or mDNS setting. This frees UDP 5353 for the container. Trade-off: the NAS itself will no longer advertise over Bonjour, so Time Machine discovery, Finder hostname visibility, and similar features go away.
3. **Run the container on a macvlan network** instead of host networking. This is the option to reach for if you want to keep the host's own Bonjour working (so you don't have to take the trade-off in option 2). Macvlan gives the container its own MAC and IP on your LAN, so its Avahi is on a different network endpoint from the host's and the two stop fighting over port 5353. **I have not tested this setup myself** and can't offer specific configuration guidance; one user reported success with it in #42 and the [Docker macvlan docs](https://docs.docker.com/network/drivers/macvlan/) are a reasonable starting point. Macvlan generally requires a wired Ethernet parent interface and does not work over Wi-Fi or on Docker Desktop.

If none of the above works, pinning the image to `1.2.0` is a valid workaround while you sort it out. You'll miss future Alpine / CUPS / Avahi security updates, but the older image advertised through the static service file flow and didn't hit these conflicts as visibly.

## Add and set up printer:
* CUPS will be configurable at http://[host ip]:631 using the CUPSADMIN/CUPSPASSWORD.
* Make sure you select `Share This Printer` when configuring the printer in CUPS.

## Reliable / remote AirPrint (configuration profile)

AirPrint normally finds printers over multicast mDNS (Bonjour). On busy Wi-Fi this can be unreliable (the printer shows up only after retrying), and it does not work across subnets/VLANs or over a VPN. If you hit this, you can install an Apple **configuration profile** that pins the printer by address, so your devices connect over unicast IPP and skip discovery entirely.

The image includes a generator script:

```
docker exec cups /root/make-airprint-profile.sh [HOST]
```

* It auto-discovers every printer you've marked **Share This Printer** and writes `/config/airprint.mobileconfig` (on your mounted `/config` volume).
* `HOST` is optional. If omitted, the host's primary IPv4 address is auto-detected; the script prints what it chose and lists the host's other addresses so you can re-run with a different one if needed. Pass a value to use a stable DNS name, or a Tailscale name/IP for remote / cross-VLAN printing — for example:

  ```
  docker exec cups /root/make-airprint-profile.sh printserver.lan
  ```

To install: copy `airprint.mobileconfig` off your `/config` volume, AirDrop or email it to your iPhone/iPad/Mac, then install it via **Settings → General → VPN & Device Management**. The printer will then be available without relying on Bonjour, and reachable anywhere your device can route to the host on port 631 (e.g. over Tailscale).

Notes:
* The profile uses plain IPP (no TLS), matching this image's default. On a LAN or an encrypted overlay like Tailscale this is fine.
* If you used an auto-detected IP and it later changes (DHCP), re-run the script — or use a reserved IP / DNS name to avoid that.

