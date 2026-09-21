# Android Capture Prototype

This is a standalone JVM prototype for Cashbook's privacy-sensitive notification capture logic.

It is intentionally separated from the BeeCount application until the behavior is stable and tested.

## Privacy property under test

The most important contract is:

> For a notification from a package outside the allowlist, Cashbook must return before reading notification content.

`NotificationGatekeeper.process(..., contentSupplier)` uses a lazy supplier so this behavior is testable.

## V0.1 allowlist

- `com.tencent.mm` — WeChat
- `com.eg.android.AlipayGphone` — Alipay

No SMS, AccessibilityService or screen-capture code exists in this module.

## Run tests

With a local Gradle installation:

```bash
gradle test
```

The next integration step is to place the gatekeeper at the very beginning of an Android `NotificationListenerService`, before reading `Notification.extras`.
