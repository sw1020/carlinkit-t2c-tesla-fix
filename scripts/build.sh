#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
WORK="$BUILD/work"
BRANCH="${T2C_BRANCH:-1508}"
TESTED_APPVER="26020416.1508.1"
BASE_URL="https://cpbox.oss-cn-shenzhen.aliyuncs.com/${BRANCH}"
CPIO="${CPIO:-/opt/homebrew/opt/cpio/bin/cpio}"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

need curl
need python3
need unsquashfs
need mksquashfs
need md5
need shasum
need xxd
need patch
if [[ ! -x "$CPIO" ]]; then
  echo "GNU cpio not found at: $CPIO" >&2
  echo "Install with: brew install cpio" >&2
  exit 1
fi

rm -f "$BUILD/T2C-custom-update.img"
rm -rf "$WORK"
mkdir -p "$WORK/fw" "$WORK/customer-src"

VERSION_JSON="$WORK/version.json"
OFFICIAL_IMG="$WORK/T2C-update.img"
OFFICIAL_SWU="$WORK/update-original.swu"

printf 'Downloading firmware metadata...\n'
curl -fsSL "$BASE_URL/version.json" -o "$VERSION_JSON"

APPVER="$(python3 - "$VERSION_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as f: j=json.load(f)
print(j.get("appver", ""))
PY
)"
URL="$(python3 - "$VERSION_JSON" <<'PY'
import json, sys
with open(sys.argv[1]) as f: j=json.load(f)
print(j.get("url", ""))
PY
)"

printf 'Public appver: %s\n' "$APPVER"
if [[ "$APPVER" != "$TESTED_APPVER" && "${FORCE:-0}" != "1" ]]; then
  echo "Refusing to build: public firmware no longer matches tested version $TESTED_APPVER" >&2
  echo "Review compatibility first. Override only if intentional: FORCE=1 ./scripts/build.sh" >&2
  exit 1
fi

[[ -n "$URL" ]] || { echo "No firmware URL found in version.json" >&2; exit 1; }

printf 'Downloading official firmware...\n'
curl -fL "$URL" -o "$OFFICIAL_IMG"

# The official wrapper is: <32-char md5><two spaces>update.swu\n, 45 bytes total.
HEADER_MD5="$(head -c 32 "$OFFICIAL_IMG")"
dd if="$OFFICIAL_IMG" of="$OFFICIAL_SWU" bs=1 skip=45 2>/dev/null
ACTUAL_MD5="$(md5 -q "$OFFICIAL_SWU")"
if [[ "$HEADER_MD5" != "$ACTUAL_MD5" ]]; then
  echo "Official wrapper MD5 mismatch" >&2
  exit 1
fi
printf 'Official wrapper MD5 verified.\n'

# Extract SWU CPIO.
(
  cd "$WORK/fw"
  "$CPIO" -idmv < "$OFFICIAL_SWU" >/dev/null
)
for f in sw-description customer kernel; do
  [[ -f "$WORK/fw/$f" ]] || { echo "Missing expected SWU file: $f" >&2; exit 1; }
done

# Confirm this is the expected project before modification.
grep -q 'ly_project_name = "ly1508"' "$WORK/fw/sw-description" || {
  echo "Unexpected sw-description project; refusing to continue." >&2
  exit 1
}

# Extract SquashFS.
(
  cd "$WORK/customer-src"
  unsquashfs "$WORK/fw/customer" >/dev/null
)
SRC="$WORK/customer-src/squashfs-root"
CSS="$SRC/app/www/css/styles.css"
JS="$SRC/app/www/js/main.js"

[[ -f "$CSS" && -f "$JS" ]] || { echo "Expected web UI files not found." >&2; exit 1; }

# Guard exact original snippets before patching.
grep -q 'min-width:[[:space:]]*1024px;' "$CSS" || {
  echo "Expected CSS min-width rule not found; firmware layout may differ." >&2
  exit 1
}
grep -q 'setTimeout(rf(), 1000)' "$JS" || {
  echo "Expected JavaScript resize handler not found; firmware layout may differ." >&2
  exit 1
}

# Apply the exact, reviewable patches shipped in this repository.
(
  cd "$SRC"
  patch --batch --forward -p1 < "$ROOT/patches/styles.css.patch"
  patch -l --batch --forward -p1 < "$ROOT/patches/main.js.patch"
)

# Confirm both patches landed exactly as expected.
grep -q 'min-width:[[:space:]]*0;' "$CSS" || {
  echo "CSS patch verification failed." >&2
  exit 1
}
grep -q 'setTimeout(rf, 1000)' "$JS" || {
  echo "JavaScript patch verification failed." >&2
  exit 1
}

# Rebuild customer with parameters observed in official firmware.
CUSTOMER_MOD="$WORK/customer-mod"
mksquashfs "$SRC" "$CUSTOMER_MOD" \
  -comp xz \
  -b 262144 \
  -noappend \
  -xattrs \
  -exports \
  -all-root \
  -nopad >/dev/null

# Build SWU in the original order.
PKG="$WORK/package"
mkdir -p "$PKG"
cp "$WORK/fw/sw-description" "$PKG/sw-description"
cp "$CUSTOMER_MOD" "$PKG/customer"
cp "$WORK/fw/kernel" "$PKG/kernel"
chmod 755 "$PKG/sw-description" "$PKG/customer" "$PKG/kernel"

CUSTOM_SWU="$WORK/update-custom.swu"
(
  cd "$PKG"
  printf '%s\n' sw-description customer kernel | \
    "$CPIO" -o -H crc -R 0:0 > "$CUSTOM_SWU"
)

MAGIC="$(xxd -p -l 6 "$CUSTOM_SWU")"
[[ "$MAGIC" == "303730373032" ]] || { echo "Generated SWU is not CPIO CRC (070702)." >&2; exit 1; }

CUSTOM_MD5="$(md5 -q "$CUSTOM_SWU")"
FINAL="$BUILD/T2C-custom-update.img"
printf '%s  update.swu\n' "$CUSTOM_MD5" > "$FINAL"
cat "$CUSTOM_SWU" >> "$FINAL"

printf '\nBuilt: %s\n' "$FINAL"
printf 'Full IMG MD5: %s\n' "$(md5 -q "$FINAL")"
printf 'Embedded SWU MD5: %s\n' "$CUSTOM_MD5"

"$ROOT/scripts/verify.sh" "$FINAL"
