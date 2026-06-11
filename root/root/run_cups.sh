#!/bin/sh
set -e
set -x

# Apply TZ if provided. Falls through to the image default (UTC) on missing
# tzdata or invalid zone names so a typo can't keep the container from booting.
if [ -n "$TZ" ]; then
    if [ -f "/usr/share/zoneinfo/$TZ" ]; then
        ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
        echo "$TZ" > /etc/timezone
        echo "Timezone set to $TZ"
    else
        echo "Warning: TZ=$TZ is not a valid zone, leaving system as UTC"
    fi
fi

# Is CUPSADMIN set? If not, set to default
if [ -z "$CUPSADMIN" ]; then
    CUPSADMIN="cupsadmin"
fi

# Is CUPSPASSWORD set? If not, set to $CUPSADMIN
if [ -z "$CUPSPASSWORD" ]; then
    CUPSPASSWORD=$CUPSADMIN
fi

if [ $(grep -ci $CUPSADMIN /etc/shadow) -eq 0 ]; then
    adduser -S -G lpadmin --no-create-home $CUPSADMIN
fi
echo $CUPSADMIN:$CUPSPASSWORD | chpasswd

# Ensure AirPrint clients can submit print jobs without a password prompt.
#
# iOS/macOS print using Create-Job + Send-Document. The stock CUPS "default"
# operation policy allows Create-Job anonymously but requires authentication
# for Send-Document/Send-URI (Require user @OWNER @SYSTEM). The device gets a
# 401 mid-print and pops a username/password dialog; if it is dismissed the
# job times out and is aborted with "no files". This was masked before v2.0
# because printers were advertised via static Avahi .service files; native
# CUPS DNS-SD registration exposes the real policy.
#
# We move only Send-Document/Send-URI into the anonymous <Limit> of the
# "default" policy so document submission succeeds without auth, while leaving
# job-management operations (cancel, hold, release, ...) owner-restricted.
#
# Runs against whatever config is active in /etc/cups/cupsd.conf, so it covers
# both fresh installs (baked-in config) and existing installs (restored from
# /config/cupsd.conf). Idempotent, and scoped to the "default" policy block so
# the "authenticated" and "kerberos" policies are left untouched.
ensure_anonymous_printing() {
    conf=/etc/cups/cupsd.conf

    # Already patched (or no such config)? Nothing to do.
    if grep -q 'Create-Job Print-Job Print-URI Validate-Job Send-Document' "$conf" 2>/dev/null; then
        return 0
    fi

    awk '
        /^[[:space:]]*<Policy default>/ { in_default = 1 }
        /^[[:space:]]*<\/Policy>/       { in_default = 0 }
        {
            if (in_default && /<Limit / && /Create-Job/ && /Print-Job/ && !/Send-Document/) {
                sub(/>[[:space:]]*$/, " Send-Document Send-URI>")
            } else if (in_default && /<Limit / && /Send-Document/ && /Hold-Job/) {
                gsub(/Send-Document /, "")
                gsub(/Send-URI /, "")
            }
            print
        }
    ' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf" \
        && echo "Patched CUPS 'default' policy to allow anonymous Send-Document (AirPrint)." \
        || rm -f "$conf.tmp"
}

mkdir -p /config/ppd
rm -rf /etc/cups/ppd
ln -s /config/ppd /etc/cups
if [ `ls -l /config/printers.conf 2>/dev/null | wc -l` -eq 0 ]; then
    touch /config/printers.conf
fi
cp /config/printers.conf /etc/cups/printers.conf

if [ `ls -l /config/cupsd.conf 2>/dev/null | wc -l` -ne 0 ]; then
    cp /config/cupsd.conf /etc/cups/cupsd.conf
else
    cp /etc/cups/cupsd.conf /config/cupsd.conf
fi

# Apply the AirPrint anonymous-printing fix to the now-active config and keep
# the persisted copy in sync so it survives restarts.
ensure_anonymous_printing

# Provide a stable, name-matching TLS certificate for ipps / DNS-SD clients.
#
# Linux CUPS clients (via cups-browsed) discover this printer over DNS-SD and
# prefer the secure ipps:// record. They then validate the server certificate.
# The default self-signed cert causes "cups-pki-invalid" for two reasons:
#   1. Name mismatch: the cert is generated for the container hostname, not the
#      mDNS name (AVAHI_HOSTNAME.local) the client actually connects to.
#   2. Trust-On-First-Use breakage: CUPS regenerates the cert on every start,
#      so a client that cached the old cert rejects the new one after a restart.
#
# Fix: pin ServerName to the advertised name (so the generated cert's SAN
# includes <name>.local), and persist the SSL keychain in /config so the cert
# is created once and reused across container recreation. AirPrint is unaffected
# (it uses plain ipp and does not validate the certificate this way).
provision_tls() {
    tls_name="${AVAHI_HOSTNAME:-cups-airprint}"

    # Persist the CUPS SSL keychain across container recreation.
    mkdir -p /config/ssl
    if [ ! -L /etc/cups/ssl ]; then
        rm -rf /etc/cups/ssl
        ln -s /config/ssl /etc/cups/ssl
    fi
    chown root:lp /config/ssl 2>/dev/null || true
    chmod 700 /config/ssl 2>/dev/null || true

    # Pin ServerName so the auto-generated certificate matches the mDNS name
    # clients connect to over ipps://. ServerAlias * is already set, so this
    # does not restrict which Host headers are accepted.
    if ! grep -q '^ServerName ' /etc/cups/cupsd.conf; then
        echo "ServerName ${tls_name}" >> /etc/cups/cupsd.conf
    fi
}
provision_tls

cp /etc/cups/cupsd.conf /config/cupsd.conf

# Function to handle cleanup on exit
cleanup() {
    echo "Cleaning up..."
    # Kill any running avahi-daemon processes
    if [ -f /var/run/avahi-daemon/pid ]; then
        PID=$(cat /var/run/avahi-daemon/pid)
        if kill -0 $PID 2>/dev/null; then
            kill $PID
            rm -f /var/run/avahi-daemon/pid
        fi
    fi
    
    # Kill any running printer-update.sh processes
    pkill -f printer-update.sh || true
    
    exit 0
}

# Set up trap for cleanup
trap cleanup SIGTERM SIGINT

# Ensure any stale PID files are removed before starting
if [ -f /var/run/avahi-daemon/pid ]; then
    rm -f /var/run/avahi-daemon/pid
fi
if [ -f /var/run/avahi-daemon.pid ]; then
    rm -f /var/run/avahi-daemon.pid
fi

# Start avahi-daemon service in the background
/root/avahi-service.sh &
AVAHI_SERVICE_PID=$!

# Wait a moment to ensure avahi-daemon has started and created its PID file
echo "Waiting for D-Bus and Avahi to be ready..."
for i in $(seq 1 30); do
    if [ -S /run/dbus/system_bus_socket ] && [ -f /var/run/avahi-daemon/pid ]; then
        echo "D-Bus and Avahi ready after ${i}s"
        break
    fi
    sleep 1
done

# Start CUPS and printer update
/root/printer-update.sh &
exec /usr/sbin/cupsd -f
