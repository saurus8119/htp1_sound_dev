# HTP-1 AirPlay addon

AirPlay 2 receiver based on Shairport Sync 5.6.1 and NQPTP 1.2.9 (SMI11), aligned with the
upstream `htp1-app/htp1-addons` implementation. The receiver routes to
`default:I2S`; AirPlay 2 discovery requires Avahi, so the package carries the
Debian 9 ARMHF `avahi-daemon` and `libavahi-core7` packages for offline install.

The CI artifact separates the installable `.tar.gz` and checksum from diagnostic
reports. Only the `.tar.gz` is attached as the release package asset. CI cannot
prove runtime library compatibility or physical playback; hardware validation is
still required.

Release 2.0.34: build and publish the installable HTP-1 addon package.

## HTPlay-1 local control page (development)

The development page at `/addons/airplay2/` adds receiver status, Start/Stop/Restart,
a five-second log snapshot viewer with the existing download link, and a narrowly
scoped `diagnostics.log_verbosity` selector (0–2). Saving verbosity first backs
up the current configuration to `etc/shairport-sync.conf.bak`; restarting the
receiver applies it. No audio, clock, buffering, decoder, or discovery settings
are editable from this page.

The companion `htplay1-control.service` listens on TCP port 17821. It accepts
connections only from IPv4 private LAN ranges (10/8, 172.16/12, 192.168/16)
and loopback. It has no separate password prompt; this is intentionally a
LAN-only personal maintenance interface, not an internet-facing service. Do
not forward port 17821 from your router or expose it outside your trusted LAN.
The browser page talks to the HTP-1's hostname on port 17821.

The development GitHub Actions workflow builds the ARMv7 service binary,
packages the addon, verifies the archive contents and uploads a temporary
artifact. It does not create a GitHub Release, update the production catalog,
or publish anything to the production repository.
