#!/bin/sh
# Build the VPN app ipk from app/ and install it, openvpn, tv/vpn and the boot hook on the TV (ssh host "tv").
# deploy.sh [profiles-dir]: also push profiles-dir/*.ovpn and profiles-dir/creds.
set -eu

ID=local.vpn
VER=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$(dirname "$0")/app/appinfo.json")
D=$(cd "$(dirname "$0")" && pwd)
W=$D/build/ipk
IPK=$D/out/${ID}_${VER}_all.ipk

rm -rf "$W" && mkdir -p "$W/data/usr/palm/applications/$ID" "$W/data/usr/palm/packages/$ID" "$D/out"
cp "$D"/app/* "$W/data/usr/palm/applications/$ID/"
printf '{"id":"%s","version":"%s","app":"%s"}\n' $ID "$VER" $ID > "$W/data/usr/palm/packages/$ID/packageinfo.json"
cat > "$W/control" <<EOF
Package: $ID
Version: $VER
Section: misc
Priority: optional
Architecture: all
Installed-Size: $(du -sb "$W/data" | cut -f1)
Maintainer: N/A <nobody@example.com>
Description: OpenVPN on/off
webOS-Package-Format-Version: 2
webOS-Packager-Version: x.y.x
EOF
printf '2.0\n' > "$W/debian-binary"
tar -czf "$W/control.tar.gz" -C "$W" --owner=0 --group=0 control
tar -czf "$W/data.tar.gz" -C "$W/data" --owner=0 --group=0 usr
# BSD-style ar: webOS fails to extract GNU ar's "name/" members
bsdtar -cf "$IPK" --format=arbsd --uid 0 --gid 0 -C "$W" debian-binary control.tar.gz data.tar.gz
echo "Built $IPK"

T=/media/developer/vpn
# temp file + rename: openvpn and vpn may be running (ETXTBSY, or sh reading a rewritten script)
put() { ssh tv "cat > $2.new && chmod $3 $2.new && mv $2.new $2" < "$1"; }

echo "Deploying..."
ssh tv "mkdir -p $T"
put "$D/out/openvpn" $T/openvpn 755
put "$D/tv/vpn" $T/vpn 755
put "$D/tv/vpn-autostart" /var/lib/webosbrew/init.d/vpn 755
if [ $# -gt 0 ]; then
    for f in "$1"/*.ovpn; do put "$f" "$T/$(basename "$f")" 600; done
    put "$1/creds" $T/creds 600
fi
ssh tv "cat > /tmp/$ID.ipk" < "$IPK"
ssh tv "luna-send -n 1 luna://com.webos.appInstallService/dev/install \
    '{\"id\":\"$ID\",\"ipkUrl\":\"/tmp/$ID.ipk\",\"subscribe\":false}' </dev/null"
