#!/usr/bin/env bash
# Print CRI-O's image storage root. Run as root (reads CRI-O config).
#   sudo bash deploy/crio_root.sh
# Newer crictl versions don't report it in `crictl info`, so fall back to
# CRI-O's config, then containers/storage.conf (which CRI-O reads by default).
set -uo pipefail

root="$(crictl info 2>/dev/null | grep -o '"root": "[^"]*"' | head -1 | cut -d'"' -f4)"
[[ -z "$root" ]] && root="$(grep -hsE '^[[:space:]]*root[[:space:]]*=' /etc/crio/crio.conf /etc/crio/crio.conf.d/*.conf | tail -1 | cut -d'"' -f2)"
[[ -z "$root" ]] && root="$(grep -sE '^[[:space:]]*graphroot[[:space:]]*=' /etc/containers/storage.conf | head -1 | cut -d'"' -f2)"
[[ -z "$root" ]] && root="/var/lib/containers/storage"   # CRI-O's built-in default
echo "$root"
