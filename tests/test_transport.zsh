#!/bin/zsh
source ${0:A:h}/helpers.zsh
COLDPRINT_LIB=1 source ${0:A:h}/../coldprint

assert_eq "ippusb is usb" \
    "usb" "$(classify_transport 'ippusb://Example%20Laser%201000._ipp._tcp.local./?uuid=00000000-aaaa')"
assert_eq "legacy usb scheme" \
    "usb" "$(classify_transport 'usb://Example/Laser-1000')"
assert_eq "explicit ipps is encrypted" \
    "ipps" "$(classify_transport 'ipps://PRN000000000000.local.:631/ipp/print')"
assert_eq "dnssd advertising _ipps is encrypted" \
    "ipps" "$(classify_transport 'dnssd://Example%20Laser%202000._ipps._tcp.local./?uuid=00000000-bbbb')"
assert_eq "dnssd advertising _ipp is cleartext" \
    "cleartext" "$(classify_transport 'dnssd://Example(R)%20Inkjet%20500._ipp._tcp.local./?uuid=00000000-cccc')"
assert_eq "plain ipp is cleartext" \
    "cleartext" "$(classify_transport 'ipp://PRN000000000000.local.:631/ipp/print')"
assert_eq "socket is cleartext" \
    "cleartext" "$(classify_transport 'socket://192.168.1.50:9100')"
assert_eq "lpd is cleartext" \
    "cleartext" "$(classify_transport 'lpd://192.168.1.50/queue')"
assert_eq "http is cleartext" \
    "cleartext" "$(classify_transport 'http://192.168.1.50:631/printers/x')"
assert_eq "unrecognised is unknown" \
    "unknown" "$(classify_transport 'weirdproto://somewhere')"

_lpstat_v() {
    cat <<'FIXTURE'
device for Laser_1000_usb: ippusb://Example%20Laser%201000._ipp._tcp.local./?uuid=00000000-aaaa
device for Laser_1000_legacy: ipp://PRN000000000000.local.:631/ipp/print
device for Laser_2000_tls: dnssd://Example%20Laser%202000._ipps._tcp.local./?uuid=00000000-bbbb
device for Inkjet_500_legacy: dnssd://Example(R)%20Inkjet%20500._ipp._tcp.local./?uuid=00000000-cccc
FIXTURE
}

assert_eq "safe transports sort first, cleartext last" \
"Laser_1000_usb	usb
Laser_2000_tls	ipps
Laser_1000_legacy	cleartext
Inkjet_500_legacy	cleartext" \
    "$(enumerate_printers)"

_lpstat_v() { return 1 }
assert_eq "no printers yields empty output" "" "$(enumerate_printers)"

finish
