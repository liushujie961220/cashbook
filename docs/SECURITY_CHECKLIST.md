# Security Checklist

Use this before every personal release.

## Android

- [ ] No READ_SMS / RECEIVE_SMS permission.
- [ ] No AccessibilityService enabled by default.
- [ ] No MediaProjection/background capture path enabled.
- [ ] Notification listener has immediate package allowlist.
- [ ] Raw notification text is not stored.
- [ ] Raw notification text is not logged in release builds.
- [ ] OCR source images are not uploaded by default.
- [ ] No ad/analytics SDK.
- [ ] No third-party crash SDK unless explicitly reviewed.
- [ ] Tokens/passwords are not written to logs.

## Cloud

- [ ] Public registration disabled.
- [ ] Strong unique bootstrap password.
- [ ] Random 32+ byte JWT secret.
- [ ] HTTPS or private overlay network in use.
- [ ] Port 8869 is not unintentionally exposed.
- [ ] Docker log rotation enabled.
- [ ] Data directory is backed up.
- [ ] Restore procedure has been tested.

## Data boundary

Allowed to sync:

- structured transactions
- accounts/categories/budgets/tags
- shared-ledger membership/profile information required by the product

Forbidden by default:

- raw notification payloads
- SMS bodies
- raw screenshots
- full OCR text
- OTP/verification codes
- passwords/tokens
