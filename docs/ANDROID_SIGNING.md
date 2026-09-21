# Android Release Signing

Cashbook uses two different signing modes.

## CI test APK

Feature-branch CI may build an installable APK using BeeCount's temporary CI signing fallback.

That APK is only for functional testing. A later build may use a different certificate, so it is not the long-term upgrade channel.

## Official GitHub Release

Official tagged releases must use one stable Cashbook keystore.

Never commit the keystore or its passwords to this public repository.

Required GitHub Actions secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

### Generate once

Run locally on a trusted machine:

```bash
keytool -genkeypair \
  -keystore cashbook-release.jks \
  -alias cashbook \
  -keyalg RSA \
  -keysize 3072 \
  -validity 10000
```

Keep `cashbook-release.jks` and the passwords in a durable private backup.

Then convert the keystore to base64 for the GitHub secret:

Linux:

```bash
base64 -w 0 cashbook-release.jks
```

macOS:

```bash
base64 < cashbook-release.jks | tr -d '\n'
```

Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("cashbook-release.jks"))
```

Store the resulting text as `ANDROID_KEYSTORE_BASE64`.

## Important

Once the first official Cashbook APK is installed, keep using the same keystore forever. Android only permits in-place upgrades when the signing identity is compatible.

The keystore is not required on the Cashbook server and must never be uploaded to the VPS.
