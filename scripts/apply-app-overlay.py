#!/usr/bin/env python3
from __future__ import annotations

import shutil
import sys
from pathlib import Path


def replace_once(path: Path, needle: str, replacement: str, marker: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        return
    if needle not in text:
        raise SystemExit(f"Expected injection point not found in {path}: {needle!r}")
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def remove_block(path: Path, block: str) -> None:
    text = path.read_text(encoding="utf-8")
    if block in text:
        path.write_text(text.replace(block, "", 1), encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: apply-app-overlay.py <beecount-dir> <overlay-dir>")

    app_root = Path(sys.argv[1]).resolve()
    overlay_root = Path(sys.argv[2]).resolve()

    if not app_root.is_dir():
        raise SystemExit(f"BeeCount directory not found: {app_root}")
    if not overlay_root.is_dir():
        raise SystemExit(f"Overlay directory not found: {overlay_root}")

    # 1) Copy Cashbook-owned files into the pinned BeeCount tree.
    for source in overlay_root.rglob("*"):
        if source.is_dir():
            continue
        relative = source.relative_to(overlay_root)
        target = app_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    # 2) Register the narrow native Flutter bridge.
    main_activity = app_root / "android/app/src/main/kotlin/com/tntlikely/beecount/MainActivity.kt"
    bridge_anchor = '        android.util.Log.e("MainActivity", "LoggerPlugin.setup 调用完成")\n'
    bridge_injection = bridge_anchor + """
        // Cashbook privacy-first payment notification bridge.
        // Raw notification text never crosses this channel.
        CashbookNotificationBridge.register(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
"""
    replace_once(
        main_activity,
        bridge_anchor,
        bridge_injection,
        "CashbookNotificationBridge.register(",
    )

    # 3) Register the NotificationListenerService.
    manifest = app_root / "android/app/src/main/AndroidManifest.xml"
    app_close = "    </application>\n"
    service_injection = """        <!-- Cashbook: privacy-first local payment-notification capture. -->
        <service
            android:name=".CashbookNotificationCaptureService"
            android:label="@string/app_name"
            android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.service.notification.NotificationListenerService" />
            </intent-filter>
        </service>

    </application>
"""
    replace_once(
        manifest,
        app_close,
        service_injection,
        'android:name=".CashbookNotificationCaptureService"',
    )

    # 4) V0.1 does not need broad gallery-reading permissions.
    remove_block(
        manifest,
        '    <!-- Required for reading screenshots (Android 13+) -->\n'
        '    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />\n',
    )
    remove_block(
        manifest,
        '    <!-- Required for reading screenshots (Android 10-12) -->\n'
        '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"\n'
        '        android:maxSdkVersion="32" />\n',
    )

    # 5) Flutter candidate intake: structured fields only.
    main_dart = app_root / "lib/main.dart"
    import_anchor = "import 'services/platform/app_link_service.dart';\n"
    import_injection = (
        import_anchor
        + "import 'services/automation/cashbook_notification_capture_service.dart';\n"
    )
    replace_once(
        main_dart,
        import_anchor,
        import_injection,
        "cashbook_notification_capture_service.dart",
    )

    init_anchor = "  await _initializeAppMode(container);\n"
    init_injection = init_anchor + """
  // Cashbook: collect sanitized payment candidates from the Android native
  // queue. Auto-confirm remains opt-in and is disabled by default.
  if (Platform.isAndroid) {
    unawaited(CashbookNotificationCaptureService(container).initialize());
  }
"""
    replace_once(
        main_dart,
        init_anchor,
        init_injection,
        "CashbookNotificationCaptureService(container).initialize()",
    )

    # 6) Do not restore BeeCount's automatic screenshot monitoring in Cashbook V0.1.
    screenshot_restore = (
        "  // 恢复截图自动识别设置（Android专属），传入container\n"
        "  await _restoreScreenshotMonitor(container);\n"
    )
    remove_block(main_dart, screenshot_restore)


    # 7) Replace BeeCount's Android screenshot-auto-billing page with the
    # Cashbook notification review / privacy page.
    auto_billing_page = app_root / "lib/pages/automation/auto_billing_settings_page.dart"
    page_import_anchor = "import 'ios_auto_billing_page.dart';\\n"
    page_import_injection = (
        page_import_anchor
        + "import 'cashbook_notification_billing_page.dart';\\n"
    )
    replace_once(
        auto_billing_page,
        page_import_anchor,
        page_import_injection,
        "cashbook_notification_billing_page.dart",
    )
    android_route = "      return const AndroidAutoBillingPage();\\n"
    cashbook_route = "      return const CashbookNotificationBillingPage();\\n"
    replace_once(
        auto_billing_page,
        android_route,
        cashbook_route,
        "return const CashbookNotificationBillingPage();",
    )

    print("Cashbook app overlay applied successfully.")


if __name__ == "__main__":
    main()
