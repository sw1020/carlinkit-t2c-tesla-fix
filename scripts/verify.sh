#!/usr/bin/env bash
set -euo pipefail

IMG="${1:-}"
[[ -n "$IMG" ]] || { echo "Usage: $0 path/to/T2C-custom-update.img" >&2; exit 2; }
[[ -f "$IMG" ]] || { echo "File not found: $IMG" >&2; exit 2; }

CPIO="${CPIO:-/opt/homebrew/opt/cpio/bin/cpio}"
[[ -x "$CPIO" ]] || { echo "GNU cpio not found at $CPIO" >&2; exit 1; }
for x in md5 shasum xxd unsquashfs grep; do
  command -v "$x" >/dev/null 2>&1 || { echo "Missing: $x" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HEAD="$(head -c 32 "$IMG")"
dd if="$IMG" of="$TMP/update.swu" bs=1 skip=45 2>/dev/null
ACTUAL="$(md5 -q "$TMP/update.swu")"
[[ "$HEAD" == "$ACTUAL" ]] || { echo "FAIL: outer MD5 wrapper mismatch" >&2; exit 1; }

MAGIC="$(xxd -p -l 6 "$TMP/update.swu")"
[[ "$MAGIC" == "303730373032" ]] || { echo "FAIL: embedded SWU is not CPIO CRC (070702)" >&2; exit 1; }

mkdir "$TMP/cpio"
(
  cd "$TMP/cpio"
  "$CPIO" -idmv < "$TMP/update.swu" >/dev/null
)
for f in sw-description customer kernel; do
  [[ -f "$TMP/cpio/$f" ]] || { echo "FAIL: missing $f" >&2; exit 1; }
done

grep -q 'ly_project_name = "ly1508"' "$TMP/cpio/sw-description" || {
  echo "FAIL: unexpected project in sw-description" >&2; exit 1
}

mkdir "$TMP/customer"
(
  cd "$TMP/customer"
  unsquashfs "$TMP/cpio/customer" >/dev/null
)
ROOT="$TMP/customer/squashfs-root"
grep -q 'min-width:[[:space:]]*0;' "$ROOT/app/www/css/styles.css" || {
  echo "FAIL: CSS patch not present in final firmware" >&2; exit 1
}
grep -q 'setTimeout(rf, 1000)' "$ROOT/app/www/js/main.js" || {
  echo "FAIL: JavaScript patch not present in final firmware" >&2; exit 1
}

printf 'Verification PASSED\n'
printf 'IMG: %s\n' "$IMG"
printf 'IMG MD5: %s\n' "$(md5 -q "$IMG")"
printf 'SWU MD5: %s\n' "$ACTUAL"
printf 'customer SHA-256: %s\n' "$(shasum -a 256 "$TMP/cpio/customer" | awk '{print $1}')"
