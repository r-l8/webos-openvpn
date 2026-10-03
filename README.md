# webos-openvpn

OpenVPN client for rooted LG webOS TVs, with a launcher app to connect, disconnect and switch
profiles. Tested on webOS 3.5 (2017 LG OLED).

## Requirements

- Rooted TV with Homebrew Channel (https://rootmy.tv): the app runs commands via
  `org.webosbrew.hbchannel.service/exec`, the boot hook runs from `/var/lib/webosbrew/init.d`.
- SSH access to the TV as host alias `tv`.
- Kernel with TUN support (`/dev/net/tun`).
- Build host: `arm-linux-musleabihf` cross toolchain, gpg, curl, bsdtar.

## Build

    ./build.sh

Builds a static armv7 hard-float OpenVPN with OpenSSL and libcap-ng into `out/openvpn`.
Release tarballs are checked against pinned OpenPGP fingerprints (OpenVPN, OpenSSL) and a pinned
sha256 (libcap-ng, unsigned upstream).

## Deploy

Put your provider's profiles and credentials in a directory outside this repo:

    profiles/NAME.ovpn ...   one per server; NAME (no spaces) is shown in the app
    profiles/creds           username and password on two lines (shared by all profiles)

Then:

    ./deploy.sh path/to/profiles

This installs to `/media/developer/vpn/` on the TV (`openvpn`, `vpn`, profiles, `creds` mode 600),
installs the boot hook as `/var/lib/webosbrew/init.d/vpn` and installs the app (`local.vpn`).
Without an argument only the app, `openvpn`, `vpn` and the boot hook are updated.
A running openvpn keeps using the old binary and script until the next connect or reboot.
Profiles removed locally are not removed from the TV.

## Use

App "VPN" on the launcher: up/down select a profile, Connect/Disconnect, Reconnect (with
the selected profile; switches profile while connected).

Shell on the TV:

    /media/developer/vpn/vpn up [profile] | down | restart [profile] | status | list

The last profile used is stored in `/media/developer/vpn/profile` and connected at every boot.
Remove `/var/lib/webosbrew/init.d/vpn` to disable that. Log: `/tmp/openvpn.log`.

## How it works

- Routes come from the server (`redirect-gateway def1`); LAN traffic stays on the LAN.
- DNS: webOS resolves through connmand, which keeps long-lived sockets to the LAN resolver, so
  DNS would bypass the tunnel. On connect, the first `dhcp-option DNS` pushed by the server is
  bind-mounted over `/var/lib/misc/resolv.conf` (the target of `/etc/resolv.conf`); unmounted on
  disconnect. If `status` shows `dns stuck`, run `vpn down`.
- `vpn up` closes file descriptors inherited from the Homebrew Channel service; otherwise
  openvpn keeps its luna-bus sockets open and later `exec` calls hang.
- The app is ES5 only (webOS 3.x web engine).

## Limitations

- No kill switch: before the tunnel is up (including at boot) and after openvpn exits, traffic
  goes out unencrypted via the normal gateway.
- IPv4 only: IPv6 traffic is not tunnelled. On a network with IPv6 it bypasses the VPN.
- `--script-security 2` also allows scripts named in the `.ovpn` (`up`, `ipchange`, ...) to run as
  root. Only use profiles you trust.
- The boot hook runs on cold boot only, not when the TV resumes from standby (Quick Start+).
