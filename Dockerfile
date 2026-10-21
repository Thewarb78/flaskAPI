set -u

# --- Known-bad material ---------------------------------------------------------
# Roots (certificate SHA-256)
declare -A ROOTS=(
  [86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B]="emSign ECC Root CA - G3"
  [D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4]="AAA Certificate Services (Sectigo/Comodo)"
  [7DD78D5F4F13459A83DFF9ABBBA62EDBAF6F2D102BF257FD712F4D9F2746ED8D]="emSign Root TLS CA - G3"
  [F2EDAAFF3D9B701FB4D14C9F285F8C0BAD90FC3BCC1FA07D47F4718EDABA34A5]="emSign Root CS CA - G3"
)
# Compromised intermediate keys (SPKI SHA-256): catches both the eMudhra and Sectigo copies
declare -A BADKEYS=(
  [EBED6475C2C2D80FCB199F3FE8DD6E6B3CE60B77EB15D4E42C3DEC0C6F5B5105]="EM DV TLS CA - G3B"
  [43BFFA19D6EF651451F6841E019931E96F6F2EAEFF28AB4B6F1CE4576DE2717B]="EM OV TLS CA - G3B"
  [E0254C7FCDC265E2F0F8A428DABB75AB4AE039B4872D62F5EE57F0877D5A8A41]="EM EV TLS CA - G3B"
  [49DD353DC2B919A3770645117D0E60C16115E7D1BC259EEFE734B00EA434FE5F]="EM DV TLS CA - G3C"
  [63ECEFEE431D49523BC1136C4E72D0206A477086CAF606CD5CF025686C109CF8]="EM OV TLS CA - G3C"
  [5C0660A2B164910D8FF589C18E14552E9E0EC237DCEFE2CB736D41A4811F81A0]="EM EV TLS CA - G3C"
  [EC4FFA1AD0AC88081314B7AAFFEF6A91F97CD57291BB5BA686C5415F5EB4F6B6]="EM OV CS CA - G3B (code signing)"
  [92C063D67E8F14DB71D288E11266FFDAF69CBF115F7BAB14F3BC2F68D25E0E30]="EM OV CS CA - G3C (code signing)"
)

PRUNE='/proc /sys /dev /run /snap /var/lib/docker /var/lib/containerd'
roots_found=0; bad_found=0; files=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

info()   { printf '\n== %s\n' "$1"; }
report() {  # $1=root|bad  $2=where  $3=what
  if [ "$1" = root ]; then
    printf '  \033[33mROOT\033[0m             %s\n                   in %s\n' "$3" "$2"; roots_found=1
  else
    printf '  \033[31mCOMPROMISED KEY\033[0m  %s\n                   in %s\n' "$3" "$2"; bad_found=1
  fi
}

find_files() {
  local prune_args=() d
  for d in $PRUNE; do prune_args+=(-path "$d" -prune -o); done
  find / -xdev "${prune_args[@]}" -type f \( "$@" \) -print 2>/dev/null | sort -u
}

# Split a PEM file into single certs and check each one's fingerprint and key hash
scan_pem() {  # $1 = file, $2 = label (optional)
  local src=$1 label=${2:-$1} c fp spki
  rm -f "$TMP"/c.*
  awk -v d="$TMP" '
    /-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("%s/c.%05d", d, n) }
    f { print > f }
    /-----END CERTIFICATE-----/   { close(f); f = "" }' "$src" 2>/dev/null
  for c in "$TMP"/c.*; do
    [ -e "$c" ] || return 0
    fp=$(openssl x509 -in "$c" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 | tr -d ':')
    [ -z "$fp" ] && continue
    if [ -n "${ROOTS[$fp]:-}" ]; then report root "$label" "${ROOTS[$fp]}"; continue; fi
    spki=$(openssl x509 -in "$c" -noout -pubkey 2>/dev/null \
           | openssl pkey -pubin -outform DER 2>/dev/null \
           | openssl dgst -sha256 -r | cut -d' ' -f1 | tr 'a-f' 'A-F')
    [ -n "$spki" ] && [ -n "${BADKEYS[$spki]:-}" ] && report bad "$label" "${BADKEYS[$spki]}"
  done
  return 0
}

command -v openssl >/dev/null || { echo "openssl not found"; exit 3; }
[ "$(id -u)" -ne 0 ] && echo "(not root: some paths may be skipped)"

# --- 1. Package status ------------------------------------------------------------
info "ca-certificates package"
if command -v dpkg-query >/dev/null && [ -r /etc/os-release ]; then
  os_id=$(. /etc/os-release; echo "${ID:-}")
  os_ver=$(. /etc/os-release; echo "${VERSION_ID:-}")
  cur=$(dpkg-query -W -f='${Version}' ca-certificates 2>/dev/null)
  fixed=""
  case "$os_id:$os_ver" in
    ubuntu:22.04|ubuntu:24.04|ubuntu:26.04|ubuntu:26.10) fixed="20260816ubuntu0.${os_ver}.1" ;;
  esac
  if [ -z "$cur" ]; then
    echo "  not installed"
  elif [ -z "$fixed" ]; then
    echo "  $os_id $os_ver, version $cur: no patched version known for this release, check Launchpad bug 2171507"
  elif dpkg --compare-versions "$cur" ge "$fixed"; then
    echo "  $cur: patched (>= $fixed)"
  else
    echo "  $cur: NOT patched, needs >= $fixed  (apt-get install --only-upgrade ca-certificates)"
  fi
else
  echo "  not a dpkg-based system, skipped"
fi

# --- 2. PEM files: OS bundle, Python bundles, vendor bundles, loose certs --------
info "PEM certificate files (OS bundle, certifi, botocore, vendor bundles, loose certs)"
while IFS= read -r f; do
  grep -q -e '-----BEGIN CERTIFICATE-----' "$f" 2>/dev/null || continue
  files=$((files + 1))
  scan_pem "$f"
done < <(find_files -name '*.pem' -o -name '*.crt' -o -name '*.cer')
echo "  scanned $files files"

# --- 3. Java keystores ----------------------------------------------------------
info "Java keystores (cacerts)"
while IFS= read -r f; do
  kt=$(command -v keytool 2>/dev/null)
  [ -x "$(dirname "$f")/../../bin/keytool" ] && kt="$(dirname "$f")/../../bin/keytool"
  if [ -z "$kt" ]; then echo "  $f: no keytool available, skipped"; continue; fi
  "$kt" -list -rfc -keystore "$f" -storepass changeit >"$TMP/ks.pem" 2>/dev/null \
    || printf '\n' | "$kt" -list -rfc -keystore "$f" >"$TMP/ks.pem" 2>/dev/null  # non-default password: list unverified
  echo "  checked $f"
  scan_pem "$TMP/ks.pem" "$f (Java keystore)"
done < <(find_files -name 'cacerts')

# --- Summary --------------------------------------------------------------------
echo
if [ "$bad_found" -eq 1 ]; then
  echo "RESULT: compromised intermediate key(s) found on disk. Find out what put them there and escalate."
  exit 2
elif [ "$roots_found" -eq 1 ]; then
  echo "RESULT: affected roots still trusted. Update ca-certificates / certifi / JDK / vendor packages."
  exit 1
fi
echo "RESULT: nothing found."
exit 0