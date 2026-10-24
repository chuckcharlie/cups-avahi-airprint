# chuckcharlie/cups-avahi-airprint

Fork from [quadportnick/docker-cups-airprint](https://github.com/quadportnick/docker-cups-airprint)

**Docker Hub:** [hub.docker.com/r/chuckcharlie/cups-avahi-airprint](https://hub.docker.com/r/chuckcharlie/cups-avahi-airprint) — `docker pull chuckcharlie/cups-avahi-airprint:latest`

## Supports ARM64 and AMD64
Use the *latest* or *version#* tags to auto choose the right architecture.

This Alpine-based Docker image runs a CUPS instance that is meant as an AirPrint relay for printers that are already on the network but not AirPrint capable.

## How it works

CUPS registers shared printers directly with Avahi via D-Bus for mDNS/DNS-SD advertisement. When you add a printer in CUPS and mark it as shared, it automatically becomes discoverable by iPhones, iPads, and Macs on your network -- no extra configuration needed.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full version history.

> **⚠️ Upgrading from a pre-v2.0 version?** Remove `- /var/run/dbus:/var/run/dbus` from your compose file or `docker run` command if it's there. Pre-v2.0 this bind mount was harmless, but as of v2.0 the container runs its own `dbus-daemon`, which will write into that shared directory and clobber the host's system D-Bus socket — breaking host services like systemd, smartd, and management UIs until the container is removed. This is most visible on NAS platforms but affects any host.

## Configuration

### Volumes:
* `/config`: persistent printer configuration, including `/config/ssl`, which holds the self-signed TLS certificate and private key so they stay stable across container restarts. Keep this volume private.

### Variables:
* `CUPSADMIN`: the CUPS admin user you want created - defaults to `cupsadmin` if unspecified
* `CUPSPASSWORD`: the password for the CUPS admin user - default is the same value as `CUPSADMIN` if unspecified
* `AVAHI_HOSTNAME`: the mDNS hostname Avahi will advertise - default is `cups-airprint`. Set this to a unique name if you have multiple instances, or if the default conflicts with your host's mDNS daemon (common on NAS devices like UGreen, Synology, etc.)
* `TZ`: optional IANA timezone name (e.g. `Europe/Vienna`, `America/Los_Angeles`) used for log timestamps inside the container. Defaults to UTC if unset or invalid.
* `DEFAULT_PAPER_SIZE`: paper size used as the default for *newly added* printers - default is `Letter`. Must be one of the names in the image's `ReadyPaperSizes` (`Letter`, `Legal`, `A4`, `A5`, `A6`, `B5`, `Postcard`, plus envelope and photo sizes); anything else is ignored with a warning in the container log, since a wrong default makes iOS print to a size the printer can't feed. Existing queues keep their own default - change those in the web UI under **Set Default Options**. The value is written into the persisted `/config/cupsd.conf`, so removing the variable later does not revert to `Letter`.
* `USE_HOST_AVAHI`: set to `true` to let CUPS register printers with the *host's* `avahi-daemon` instead of starting one in the container. For hosts that already run Avahi, typically a NAS - see **Running on a NAS** for the required mount and what it grants the container. Printers are advertised under the host's own name, so `AVAHI_HOSTNAME` has no effect on discovery in this mode; leave it unset.

### Ports/Network:
* Must be run on host network. This is required to support multicasting which is needed for Airprint, and it applies with `USE_HOST_AVAHI` too - the host's Avahi advertises the host's own address, so the container has to be on it.
* **Security note:** host networking exposes the CUPS web admin and printing on port `631` to your whole LAN, the print path accepts jobs without authentication, and traffic is not meaningfully encrypted. Set a strong `CUPSADMIN`/`CUPSPASSWORD` and only run this on a trusted network.

### Example run command:
```
docker run --name cups --restart unless-stopped --net host \
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
      # TZ: "Europe/Vienna"            # optional, defaults to UTC
      # AVAHI_HOSTNAME: "cups-airprint" # optional, change if it conflicts on your network
    restart: unless-stopped
```

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
* `HOST` is optional - the host's primary IPv4 address is auto-detected, and the script prints what it chose along with the host's other addresses so you can re-run with a different one. Pass a value to use a stable DNS name, or a Tailscale name/IP for remote / cross-VLAN printing — for example:

  ```
  docker exec cups /root/make-airprint-profile.sh printserver.lan
  ```

To install: copy `airprint.mobileconfig` off your `/config` volume, AirDrop or email it to your iPhone/iPad/Mac, then install it via **Settings → General → VPN & Device Management**. The printer will then be available without relying on Bonjour, and reachable anywhere your device can route to the host on port 631 (e.g. over Tailscale).

Notes:
* The profile uses plain IPP (no TLS), matching this image's default - fine on a LAN or an encrypted overlay like Tailscale.
* If an auto-detected IP later changes (DHCP), re-run the script, or use a reserved IP / DNS name to avoid it.

## Running on a NAS

> Skip this unless your host runs its own Avahi/Bonjour daemon. Most NAS operating systems do; a plain Linux host usually doesn't.

First, remove any `- /var/run/dbus:/var/run/dbus` bind mount from your compose (see the upgrade warning under **Changelog**) - it's the most damaging misconfiguration on a NAS and takes down host services like the management UI.

NAS operating systems (TrueNAS Scale, Synology DSM, UGreen NAS OS, QNAP, etc.) typically run their own `avahi-daemon` on the host to advertise things like SMB shares, Time Machine, and Finder hostname visibility. When this container runs in host networking mode, both Avahi daemons share the host's network stack and can collide. Common symptoms:

* `bind() failed: Address in use` in the container logs, followed by `Failed to create IPv4 socket, proceeding in IPv6 only mode`. The host's Avahi already owns UDP 5353, so the container only gets IPv6 and most iOS devices never see the printer.
* A repeating `Host name conflict, retrying with <hostname>-NN` loop in the container logs. The container is trying to register the host's own hostname on mDNS.
* Printers work in the CUPS web UI but never show up in AirPrint on iOS/macOS.

Things to try, roughly in order of simplicity:

1. **Use the host's Avahi** (recommended if your NAS runs `avahi-daemon`). The container skips its own D-Bus and Avahi and lets CUPS register printers with the host's daemon, so there is only one mDNS responder and the NAS keeps advertising SMB, Time Machine, etc.:

   ```yaml
   environment:
     USE_HOST_AVAHI: "true"
   volumes:
     - ./config:/config
     - /run/dbus:/run/host-dbus:ro
   ```

   Mount the host's D-Bus directory at `/run/host-dbus`, **never** at `/run/dbus` or `/var/run/dbus` (see the upgrade warning above). The host's Avahi D-Bus policy must allow other users to publish services; the stock Debian/Ubuntu policy does.

   If the host's Avahi can't be reached - not running, or its policy refuses the connection - the container says so in its log every 10 seconds instead of looking healthy while advertising nothing. Local printing keeps working either way. The message also tells you which case you're in: CUPS registers the printers by itself once the host starts Avahi, but if the bus connection was refused it does not retry, so you have to restart the container after fixing the policy.

   Know what the mount grants: `/run/dbus` is the host's entire system bus, not an Avahi-only channel, so the container can also reach services like systemd and polkit on it. `:ro` doesn't limit that - it makes the directory read-only, and connecting to a socket isn't a write. If you'd rather not grant that, option 2 fixes the hostname-conflict case with no mount.
2. **Set `AVAHI_HOSTNAME`** to a unique value like `cups-airprint` (the default) or `mynas-print`. This avoids the hostname-conflict loop, and needs no mount or host trust - try it first if the conflict loop is your only symptom.
3. **Disable the host's mDNS/Bonjour service.** On TrueNAS Scale this is under **Network → Global Configuration**. On other NAS platforms look for a Bonjour, Avahi, or mDNS setting. This frees UDP 5353 for the container. Trade-off: the NAS itself will no longer advertise over Bonjour, so Time Machine discovery, Finder hostname visibility, and similar features go away.
4. **Run the container on a macvlan network** instead of host networking. The container gets its own MAC and IP, so its Avahi stops competing with the host's and the NAS keeps its own Bonjour - the same outcome as option 1, without granting the container any host access. Requires a wired Ethernet parent interface; it does not work over Wi-Fi or on Docker Desktop. **Untested by me**; one user reported success in #42, and the [Docker macvlan docs](https://docs.docker.com/network/drivers/macvlan/) are a reasonable starting point.

If none of these work, pinning the image to `1.2.0` is a valid stopgap - it advertised through static service files and didn't hit these conflicts, at the cost of missing future Alpine / CUPS / Avahi security updates.

