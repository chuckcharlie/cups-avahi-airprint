#!/bin/sh
# make-airprint-profile.sh
#
# Generates an Apple configuration profile (.mobileconfig) for the printers
# shared by this CUPS instance, pinning each one by hostname/IP so iPhones,
# iPads, and Macs reach it over unicast IPP instead of relying on Bonjour/mDNS
# discovery.
#
# Why: AirPrint normally finds printers via multicast mDNS, which is unreliable
# on busy Wi-Fi and does not cross subnets/VLANs or VPNs. Installing this
# profile makes the printer appear instantly and reliably, and lets you print
# from other VLANs or remotely (e.g. over Tailscale) as long as the device can
# reach the host on the IPP port.
#
# Usage:
#   docker exec cups /root/make-airprint-profile.sh [HOST]
#
#     HOST  Optional hostname or IP that Apple devices should connect to.
#           Defaults to this host's primary IPv4 address. Use a stable DNS name
#           (e.g. printserver.lan) or a Tailscale name/IP for remote printing.
#
# Output:
#   /config/airprint.mobileconfig
#   Copy it off the /config volume, AirDrop/email it to your device, then
#   install via Settings > General > VPN & Device Management.

set -eu

PRINTERS_CONF=/etc/cups/printers.conf
OUT=/config/airprint.mobileconfig
PORT=631

usage() {
    cat <<USAGE
Usage: make-airprint-profile.sh [HOST]

Generates /config/airprint.mobileconfig for the CUPS-shared printers, pinned to
HOST so Apple devices connect over unicast IPP (no Bonjour/mDNS discovery).

  HOST   Hostname or IP your Apple devices should connect to.
         If omitted, this host's primary IPv4 address is auto-detected.
         Pass a value if auto-detect is wrong, to use a stable DNS name, or a
         Tailscale name/IP for remote / cross-VLAN printing.

Examples:
  docker exec cups /root/make-airprint-profile.sh
  docker exec cups /root/make-airprint-profile.sh 192.168.1.50
  docker exec cups /root/make-airprint-profile.sh printserver.lan
USAGE
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

# --- Host that Apple devices will connect to ---
HOST="${1:-}"
AUTODETECTED=0
if [ -z "$HOST" ]; then
    HOST="$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
    AUTODETECTED=1
fi
if [ -z "$HOST" ]; then
    echo "ERROR: could not auto-detect an IP. Pass one explicitly:" >&2
    echo "  docker exec cups /root/make-airprint-profile.sh <hostname-or-ip>" >&2
    exit 1
fi

uuid() { cat /proc/sys/kernel/random/uuid; }

# --- Shared printers from printers.conf -> "<queue>|<info>" ---
get_shared_printers() {
    awk '
        /^<(Default)?Printer / { name=$2; sub(/>$/,"",name); info=name; shared=0 }
        /^Info /              { tmp=$0; sub(/^Info /,"",tmp); info=tmp }
        /^Shared Yes/         { shared=1 }
        /^<\/Printer>/        { if (shared) print name "|" info }
    ' "$PRINTERS_CONF" 2>/dev/null
}

PRINTERS="$(get_shared_printers)"
if [ -z "$PRINTERS" ]; then
    echo "No shared printers found. In the CUPS web UI mark a printer as" >&2
    echo "'Share This Printer', then re-run this script." >&2
    exit 1
fi

# --- Build the AirPrint payload entries ---
ITEMS=""
NAMES=""
OLDIFS="$IFS"
IFS='
'
for line in $PRINTERS; do
    queue="${line%%|*}"
    info="${line#*|}"
    [ -z "$info" ] && info="$queue"
    ITEMS="${ITEMS}                <dict>
                    <key>IPAddress</key>
                    <string>${HOST}</string>
                    <key>ResourcePath</key>
                    <string>printers/${queue}</string>
                    <key>Port</key>
                    <integer>${PORT}</integer>
                    <key>ForceTLS</key>
                    <false/>
                </dict>
"
    NAMES="${NAMES}${info}, "
done
IFS="$OLDIFS"

cat > "$OUT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.apple.airprint</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadIdentifier</key>
            <string>com.cups-avahi-airprint.airprint</string>
            <key>PayloadUUID</key>
            <string>$(uuid)</string>
            <key>PayloadDisplayName</key>
            <string>AirPrint Printers</string>
            <key>AirPrint</key>
            <array>
${ITEMS}            </array>
        </dict>
    </array>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadIdentifier</key>
    <string>com.cups-avahi-airprint.profile</string>
    <key>PayloadUUID</key>
    <string>$(uuid)</string>
    <key>PayloadDisplayName</key>
    <string>CUPS AirPrint Printers (${HOST})</string>
    <key>PayloadDescription</key>
    <string>Adds CUPS-shared printers as AirPrint printers by address (${HOST}:${PORT}) so Apple devices connect over unicast IPP without relying on Bonjour/mDNS discovery.</string>
    <key>PayloadOrganization</key>
    <string>cups-avahi-airprint</string>
</dict>
</plist>
EOF

echo "Wrote $OUT"
echo "Host:     ${HOST}:${PORT} (plain IPP)"
echo "Printers: ${NAMES%, }"
if [ "$AUTODETECTED" -eq 1 ]; then
    echo
    echo "NOTE: host was auto-detected. If ${HOST} is not the address your Apple"
    echo "devices should use, re-run with the correct one, e.g.:"
    echo "  docker exec cups /root/make-airprint-profile.sh printserver.lan"
    others="$(ip -4 -o addr show scope global 2>/dev/null \
        | awk '{print $4}' | cut -d/ -f1 | grep -v "^${HOST}\$" | tr '\n' ' ')"
    [ -n "$others" ] && echo "Other addresses on this host: ${others}"
fi
echo
echo "Copy it from your /config volume, AirDrop/email it to your Apple device,"
echo "then install via Settings > General > VPN & Device Management."
