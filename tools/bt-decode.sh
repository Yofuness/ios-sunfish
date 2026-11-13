#!/bin/bash
# Decode a btsnoop capture (btbridge -S / /var/local/btbridge.snoop, or btmon -w) with tshark plus the Apple
# Bluetooth dissectors of pabloaul/apple-wireshark (AACP, FastConnect, MagicPairing, Magnet, ...; GPL-3, used as a
# tool from research/upstream/apple-wireshark, not vendored). Captures hold link keys: keep them out of git.
# The plugins load as Wireshark's README installs them (personal plugin dir), but under a private HOME
# (work/wireshark-home), so the user's own Wireshark setup is untouched; `-X lua_script:` loading breaks their
# require() chains (aacp_fields.lua: global 'aacp_proto' is nil).
#   tools/bt-decode.sh CAPTURE [extra tshark args...]      e.g.  tools/bt-decode.sh ../logs/bt/x.btsnoop -Y aacp -V
#   tools/bt-decode.sh --protocols                         lists the loaded Apple protocols
set -euo pipefail
cd "$(dirname "$0")/.."
P=research/upstream/apple-wireshark/plugins
[ -d "$P" ] || { echo "missing $P: git clone https://github.com/pabloaul/apple-wireshark research/upstream/apple-wireshark"; exit 1; }
H=$PWD/work/wireshark-home
mkdir -p "$H/.local/lib/wireshark/plugins"
for d in "$P"/*/; do
	ln -sfn "$PWD/$d" "$H/.local/lib/wireshark/plugins/$(basename "$d")"
done
if [ "${1:-}" = --protocols ]; then
	HOME=$H tshark -G protocols 2>&1 | grep -iE 'aacp|fastconnect|magicpairing|magnet|uarp|nearby|alloy|rapport|cldurian|nrlp|rtbuddy'
	exit 0
fi
f=${1:?usage: $0 CAPTURE [tshark args] | --protocols}; shift
f=$(readlink -f "$f")
HOME=$H exec tshark -r "$f" "$@"
