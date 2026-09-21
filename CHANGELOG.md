# Changelog

All notable Cashbook changes are recorded here.

## [0.1.0-alpha] - 2026-09-21

### Added

- Added opt-in local privacy diagnostics for notification calibration; only source/category/channelId/outcome/time are retained, never notification content.

- Privacy-first Cashbook project foundation.
- BeeCount / BeeCount Cloud pinned-upstream overlay workflow.
- Self-hosted 2C / 2G / 40G deployment profile.
- Android WeChat and Alipay notification capture prototype.
- Immediate package allowlist before notification content is read.
- Local deterministic payment parser.
- CandidateTransaction model with confidence and fingerprint.
- Native structured candidate queue with two-minute deduplication window.
- Flutter candidate intake service.
- Manual candidate review UI.
- Optional high-confidence auto-confirm switch, disabled by default.
- Shared-ledger transaction write path using BeeCount's existing author and sync services.
- Independent Android application id: `com.liushujie.cashbook`.
- CI privacy audit, upstream overlay validation, Flutter analysis and APK build.

### Privacy

- WeChat/Alipay notifications classified by Android as ordinary messages are discarded before title/body/extras are read.
- Final prod APK is audited after Android manifest merging; media, storage, microphone, SMS and APK-install permissions are blocked.

- No SMS permissions.
- No AccessibilityService.
- No background screen capture.
- No raw payment notification persistence.
- No raw payment notification upload.
- No cloud LLM processing of raw payment notifications.
- Broad Android photo-library permissions removed from Cashbook V0.1.
- BeeCount automatic screenshot-monitor restore disabled.

### Known limitations

- WeChat / Alipay notification wording still needs real-device calibration.
- Automatic confirmation should remain off until real-device accuracy is verified.
- Android is the first supported platform for notification capture.
