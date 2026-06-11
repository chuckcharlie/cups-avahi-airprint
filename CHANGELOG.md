# Changelog

## v2.1.2

- **Stable, name-matching TLS certificate** (helps Linux clients and reduces AirPrint cert warnings): CUPS auto-generates a self-signed certificate for `ipps://` connections. Previously it was generated for the container hostname (not the advertised mDNS name) and regenerated on every container start. Linux CUPS clients discovering the printer over `ipps://` rejected it with `cups-pki-invalid`, and Apple devices could show "Encryption Credentials Changed" prompts after restarts. `run_cups.sh` now pins CUPS `ServerName` to `AVAHI_HOSTNAME` so the certificate's name matches what clients connect to, and persists the certificate in `/config/ssl` so it stays stable across container restarts and recreation. The certificate is still self-signed. **Note:** on first start of this version the certificate is regenerated once, so an iOS/macOS device that previously trusted the old certificate may show a one-time prompt to accept the new one.

## v2.1.1

- **Fixed AirPrint password prompt mid-print**: iOS/macOS print using `Create-Job` + `Send-Document`. The stock CUPS `default` policy allows `Create-Job` anonymously but requires authentication for `Send-Document`, so devices got a `401` as the job reached the server and popped a "Password required" dialog; dismissing it left the job to time out and abort with "no files". This was masked before v2.0 because printers were advertised via static Avahi `.service` files — native CUPS DNS-SD registration exposes the real operation policy. `run_cups.sh` now moves `Send-Document`/`Send-URI` into the anonymous limit of the `default` policy on startup. The patch is idempotent, scoped to the `default` policy (the `authenticated` and `kerberos` policies are untouched), and applies to both fresh installs and existing installs whose `cupsd.conf` is restored from `/config`. Job-management operations (cancel, hold, release, ...) stay owner-restricted. Note: as with any AirPrint relay, this means any host permitted by the `<Location />` block can submit print jobs without authentication.

## v2.1

- **Optional `TZ` environment variable**: set `TZ` to an IANA timezone name (e.g. `Europe/Vienna`) to make container time and CUPS log timestamps match your local zone. Defaults to UTC when unset, and falls back to UTC with a warning if the value isn't a valid zone — closes [#50](https://github.com/chuckcharlie/cups-avahi-airprint/issues/50).
- **Hardened startup ordering**: replaced the fixed `sleep 2` before launching CUPS with a readiness loop that waits for the D-Bus socket and Avahi pid file. Avoids a race on slower hosts where CUPS could start before Avahi was ready and silently fail to register printers — fixes [#49](https://github.com/chuckcharlie/cups-avahi-airprint/pull/49). Also corrects D-Bus pidfile cleanup so stale pidfiles are actually removed on container restart.
- **Build fix**: added `edge/community` to the apk repository list. Alpine moved `cups-pdf` out of `edge/main` and `edge/testing`, so the package wasn't resolving anymore.

## v2.0

- **Native DNS-SD registration**: CUPS now registers printers with Avahi directly over D-Bus, replacing the previous `airprint-generate.py` script that manually created Avahi service files. This fixes an issue where iOS devices would show duplicate printer entries due to a mismatch between the mDNS service name and the CUPS IPP response.
- **Removed `/services` volume**: No longer needed since Avahi service files are no longer generated externally.
- **Internal D-Bus daemon**: The container now runs its own `dbus-daemon` internally to support the native DNS-SD registration above.

> **Upgrading from an earlier version? Remove `- /var/run/dbus:/var/run/dbus` from your compose file or `docker run` command if it's there.** Older example configurations (including in previous versions of this README and the upstream fork) included this bind mount. It was harmless pre-v2.0 because the container never started its own bus, but as of v2.0 the container's internal `dbus-daemon` will write into that shared directory and clobber the host's system D-Bus socket, breaking host services like systemd, smartd, and management UIs until the container is removed. This is most visible on NAS platforms but affects any host.
