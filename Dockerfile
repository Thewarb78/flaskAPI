#!/usr/bin/env bash
# check-emudhra-certs.sh
# Looks for the eMudhra/emSign roots and the Sectigo "AAA Certificate Services"
# root (used by the cross-signs) in the trust stores on an Ubuntu/Debian host.
#
# Checks: OS bundle + ca-certificates.conf, Python bundles (certifi, botocore,
# other cacert.pem / ca-bundle files) and Java keystores (cacerts).
# Read-only. Run with sudo to search the whole filesystem.
# Exit code: 0 = nothing found, 1 = at least one match (handy in CI).
#
# Usage: sudo ./check-emudhra-certs.sh

set -u
PATTERN='emSign|AAA Certificate Services'
PRUNE='/proc /sys /dev /run /snap /var/lib/docker /var/lib/containerd'
found=0

info() { printf '\n== %s\n' "$1"; }
hit()  { printf '  \033[31mFOUND\033[0m %s\n' "$1"; found=1; }

# find(1) across the root filesystem, skipping virtual fs and container layers
find_files() {
  local prune_args=() d
  for d in $PRUNE; do prune_args+=(-path "$d" -prune -o); done
  find / -xdev "${prune_args[@]}" -type f \( "$@" \) -print 2>/dev/null | sort -u
}

# Print the subject of every certificate in a PEM bundle
pem_subjects() {
  openssl crl2pkcs7 -nocrl -certfile "$1" 2>/dev/null \
    | openssl pkcs7 -print_certs -noout 2>/dev/null \
    | grep '^subject'
}

check_pem() {
  local f=$1 matches m