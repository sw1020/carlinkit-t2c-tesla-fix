# CarlinKit T2C Tesla Browser Resolution Fix

A reproducible, auditable build process for a CarlinKit T2C custom firmware that fixes the CarPlay browser cropping/scaling issue observed after a Tesla browser/software update.

## What this fixes

On the tested T2C firmware, the web UI contained:

```css
body {
    min-width: 1024px;
}
```

With the newer Tesla browser viewport, this caused a visible width of roughly `773px` to be reported to the page as an effective `window.innerWidth` of `1024px`. The T2C then sent `window.innerWidth` / `window.innerHeight` to its backend during WebSocket initialization, which could make the CarPlay surface larger than the visible browser area.

The firmware patch does two things:

1. Changes `min-width: 1024px` to `min-width: 0`.
2. Changes `setTimeout(rf(), 1000)` to `setTimeout(rf, 1000)` so the resize callback is actually delayed rather than executed immediately.

## Tested configuration

- Adapter: CarlinKit T2C
- Firmware branch: `1508`
- Tested firmware: `26020416.1508.1`
- Project: `ly1508`
- Platform: Tina Linux
- Customer filesystem: SquashFS 4.0 / XZ
- SquashFS block size: `262144`
- SWUpdate archive: CPIO CRC (`070702`)
- Tesla browser test viewport: `773 x 601`
- Vehicle test: Tesla Model Y 2023

The resulting firmware was flashed and tested successfully on the above configuration.

## Important warning

This project modifies and flashes firmware. A bad image, incompatible hardware revision, interrupted update, or unexpected recovery behavior can brick the adapter.

Do **not** use the generated firmware on a different firmware branch or hardware revision unless you have independently verified compatibility.

The scripts intentionally stop when the official firmware metadata does not match the tested `1508` branch unless you explicitly override the guard.

## Why distribute a builder instead of only a firmware image?

This repository is designed so users can:

- download the official firmware themselves;
- audit exactly what changes are applied;
- rebuild the image locally;
- verify MD5/SHA-256 integrity before flashing;
- avoid trusting an opaque prebuilt binary.

## Prerequisites — macOS

Install Homebrew if needed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install tools:

```bash
brew install cpio squashfs binwalk
brew install nmap   # optional; useful for troubleshooting
```

On Apple Silicon:

```bash
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/opt/cpio/bin:$PATH"
```

Verify GNU cpio:

```bash
/opt/homebrew/opt/cpio/bin/cpio --version
```

## 1. Check your T2C before building

Connect your computer to the T2C Wi-Fi and run:

```bash
./scripts/check-device.sh
```

The script intentionally prints only the firmware-related fields needed for compatibility checking and omits serial/MAC identifiers.

Expected tested version:

```text
26020416.1508.1
```

If your device is on a different branch, stop unless you know exactly what you are doing.

## 2. Build

Run:

```bash
./scripts/build.sh
```

The script will:

1. Download `version.json` for branch `1508`.
2. Verify that the public firmware version matches the tested version.
3. Download the official `update.img`.
4. Validate the outer MD5 wrapper.
5. Extract `update.swu`.
6. Extract the CPIO payload.
7. Extract the `customer` SquashFS.
8. Apply the two source-level patches.
9. Rebuild `customer` using the original SquashFS parameters.
10. Rebuild the CRC CPIO `update.swu`.
11. Rebuild the outer MD5 wrapper.
12. Run validation on the final firmware.

Output:

```text
build/T2C-custom-update.img
```

To allow building when the metadata no longer reports the tested public version:

```bash
FORCE=1 ./scripts/build.sh
```

That override is intentionally explicit.

## 3. Verify

You can re-run validation independently:

```bash
./scripts/verify.sh build/T2C-custom-update.img
```

Verification checks:

- outer MD5 wrapper matches the embedded SWU;
- CPIO uses CRC magic `070702`;
- expected files exist;
- `customer` is valid SquashFS;
- patched CSS exists in the final image;
- patched JavaScript exists in the final image.

## 4. Flash

Connect to the T2C Wi-Fi and make sure the adapter has stable power.

```bash
curl -v \
  -F 'file=@build/T2C-custom-update.img;filename=update.img' \
  'http://192.168.3.1/cgi-bin/index.cgi?id=upload'
```

Expected response:

```json
{"code": 0, "msg": "upload successful"}
```

Do **not** disconnect power after upload. The device may reboot more than once while SWUpdate uses its recovery flow.

## 5. Confirm the patch

After the T2C Wi-Fi returns:

```bash
curl -s 'http://192.168.3.1/cgi-bin/index.cgi?id=host'
```

Then open the T2C page in Chrome, emulate a `773 x 601` viewport in DevTools, and run:

```javascript
({
  innerWidth: window.innerWidth,
  innerHeight: window.innerHeight,
  bodyWidth: document.body.getBoundingClientRect().width,
  documentWidth: document.documentElement.getBoundingClientRect().width
})
```

Expected after the patch:

```text
innerWidth:    773
innerHeight:   601
bodyWidth:     773
documentWidth: 773
```

## Patch details

### `styles.css`

```diff
-    min-width: 1024px;
+    min-width: 0;
```

### `main.js`

```diff
-        wst = this.setTimeout(rf(), 1000);
+        wst = this.setTimeout(rf, 1000);
```

## Update architecture observed during analysis

The official firmware uses SWUpdate and a recovery-oriented sequence approximately like:

```text
update.img
  -> validate/extract update.swu
  -> upgrade_recovery
  -> swu_mode=upgrade_kernel
  -> ly_boot_mode=update
  -> boot_partition=recovery
  -> reboot
  -> write kernel + customer
  -> upgrade_usr
  -> boot_partition=boot
  -> ly_boot_mode=normal
  -> reboot
```

The tested `sw-description` writes:

```text
kernel   -> /dev/by-name/boot
customer -> /dev/by-name/customer
```

No obvious A/B automatic rollback mechanism was identified.

## Documentation

A detailed PDF walkthrough is included in:

```text
docs/CarlinKit_T2C_Tesla_Resolution_Fix_Guide.pdf
```

## Privacy

Do not publish:

- serial numbers;
- UUIDs;
- Wi-Fi/Bluetooth MAC addresses;
- IMEI values;
- personal usernames in shell prompts;
- device-specific test identifiers.

## License / responsibility

Use at your own risk. This project is provided for technical research and reproducibility. It is not affiliated with or endorsed by CarlinKit, Tesla, or Apple.
