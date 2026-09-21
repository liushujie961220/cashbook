import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers.dart';
import '../billing/post_processor.dart';
import '../data/tx_author_service.dart';
import '../system/logger_service.dart';

enum CashbookCaptureSource {
  wechatNotification,
  alipayNotification,
}

enum CashbookCandidateDirection {
  expense,
  income,
}

class CashbookCandidateTransaction {
  const CashbookCandidateTransaction({
    required this.source,
    required this.amount,
    required this.direction,
    required this.occurredAt,
    required this.confidence,
    required this.fingerprint,
    this.merchant,
  });

  final CashbookCaptureSource source;
  final double amount;
  final CashbookCandidateDirection direction;
  final String? merchant;
  final DateTime occurredAt;
  final double confidence;
  final String fingerprint;

  factory CashbookCandidateTransaction.fromPlatformMap(
    Map<Object?, Object?> raw,
  ) {
    final source = switch (raw['source']?.toString()) {
      'WECHAT_NOTIFICATION' => CashbookCaptureSource.wechatNotification,
      'ALIPAY_NOTIFICATION' => CashbookCaptureSource.alipayNotification,
      _ => throw const FormatException('Unsupported notification source'),
    };
    final direction = switch (raw['direction']?.toString()) {
      'EXPENSE' => CashbookCandidateDirection.expense,
      'INCOME' => CashbookCandidateDirection.income,
      _ => throw const FormatException('Unsupported direction'),
    };
    final amountRaw = raw['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.parse(amountRaw.toString());
    final timeRaw = raw['occurredAtMillis'];
    final occurredAtMillis =
        timeRaw is num ? timeRaw.toInt() : int.parse(timeRaw.toString());
    final confidenceRaw = raw['confidence'];
    final confidence = confidenceRaw is num
        ? confidenceRaw.toDouble()
        : double.parse(confidenceRaw.toString());

    final merchantRaw = raw['merchant']?.toString().trim();
    final fingerprint = raw['fingerprint']?.toString().trim() ?? '';
    if (amount <= 0 || fingerprint.isEmpty) {
      throw const FormatException('Invalid candidate payload');
    }

    return CashbookCandidateTransaction(
      source: source,
      amount: amount,
      direction: direction,
      merchant: merchantRaw == null || merchantRaw.isEmpty ? null : merchantRaw,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(occurredAtMillis),
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      fingerprint: fingerprint,
    );
  }

  factory CashbookCandidateTransaction.fromJson(
    Map<String, dynamic> json,
  ) {
    return CashbookCandidateTransaction(
      source: CashbookCaptureSource.values.byName(json['source'] as String),
      amount: (json['amount'] as num).toDouble(),
      direction:
          CashbookCandidateDirection.values.byName(json['direction'] as String),
      merchant: json['merchant'] as String?,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        (json['occurredAtMillis'] as num).toInt(),
      ),
      confidence: (json['confidence'] as num).toDouble(),
      fingerprint: json['fingerprint'] as String,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'source': source.name,
        'amount': amount,
        'direction': direction.name,
        'merchant': merchant,
        'occurredAtMillis': occurredAt.millisecondsSinceEpoch,
        'confidence': confidence,
        'fingerprint': fingerprint,
      };

  String get paymentLabel => switch (source) {
        CashbookCaptureSource.wechatNotification => '微信',
        CashbookCaptureSource.alipayNotification => '支付宝',
      };
}

/// Cashbook Android payment-notification intake.
///
/// Privacy boundary:
/// - Dart never receives raw notification content.
/// - only the structured fields in [CashbookCandidateTransaction] cross the
///   native MethodChannel.
/// - automatic confirmation is opt-in and disabled by default.
class CashbookNotificationCaptureService {
  CashbookNotificationCaptureService._(this._container);

  static CashbookNotificationCaptureService? _instance;

  factory CashbookNotificationCaptureService(ProviderContainer container) {
    return _instance ??= CashbookNotificationCaptureService._(container);
  }

  static const MethodChannel _channel =
      MethodChannel('com.cashbook/notification_capture');

  static const _pendingKey = 'cashbook_pending_notification_candidates_v1';
  static const _processedKey = 'cashbook_processed_notification_fingerprints_v1';
  static const _autoConfirmKey = 'cashbook_notification_auto_confirm_v1';
  static const _autoConfirmThresholdKey =
      'cashbook_notification_auto_confirm_threshold_v1';

  static const double defaultAutoConfirmThreshold = 0.94;
  static const int _maxPending = 100;
  static const int _maxProcessed = 300;
  static const Duration _foregroundPollInterval = Duration(seconds: 8);

  final ProviderContainer _container;
  Timer? _pollTimer;
  bool _busy = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    await refreshCandidates();
    await processEligibleCandidates();

    _pollTimer ??= Timer.periodic(_foregroundPollInterval, (_) async {
      await refreshCandidates();
      await processEligibleCandidates();
    });
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<bool> isNotificationAccessGranted() async {
    if (!Platform.isAndroid) return false;
    return (await _channel.invokeMethod<bool>('isNotificationAccessGranted')) ??
        false;
  }

  Future<void> openNotificationAccessSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openNotificationAccessSettings');
  }

  Future<bool> isAutoConfirmEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoConfirmKey) ?? false;
  }

  Future<void> setAutoConfirmEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoConfirmKey, enabled);
    if (enabled) {
      await processEligibleCandidates();
    }
  }

  Future<double> autoConfirmThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_autoConfirmThresholdKey) ??
        defaultAutoConfirmThreshold;
  }

  Future<void> setAutoConfirmThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _autoConfirmThresholdKey,
      value.clamp(0.80, 0.99).toDouble(),
    );
  }

  Future<List<CashbookCandidateTransaction>> pendingCandidates() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadPending(prefs);
  }

  Future<void> refreshCandidates() async {
    if (!Platform.isAndroid || _busy) return;
    _busy = true;
    try {
      final rawItems =
          await _channel.invokeMethod<List<dynamic>>('drainCandidates') ??
              const <dynamic>[];
      if (rawItems.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final pending = _loadPending(prefs);
      final processed = _loadProcessed(prefs).toSet();

      for (final raw in rawItems) {
        if (raw is! Map) continue;
        try {
          final candidate = CashbookCandidateTransaction.fromPlatformMap(
            raw.cast<Object?, Object?>(),
          );
          if (processed.contains(candidate.fingerprint)) continue;

          final duplicate = pending.any((item) =>
              item.fingerprint == candidate.fingerprint &&
              item.occurredAt.difference(candidate.occurredAt).abs() <=
                  const Duration(minutes: 2));
          if (!duplicate) pending.add(candidate);
        } catch (e) {
          logger.warning(
            'CashbookCapture',
            '忽略无法解析的结构化候选（不包含原始通知）: $e',
          );
        }
      }

      pending.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      final trimmed = pending.length <= _maxPending
          ? pending
          : pending.sublist(pending.length - _maxPending);
      await _savePending(prefs, trimmed);
    } on PlatformException catch (e) {
      logger.warning(
        'CashbookCapture',
        '读取通知候选失败: ${e.code}',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> processEligibleCandidates() async {
    if (!Platform.isAndroid) return;
    if (!await isAutoConfirmEnabled()) return;

    final threshold = await autoConfirmThreshold();
    final candidates = await pendingCandidates();

    for (final candidate in candidates) {
      if (candidate.confidence < threshold) continue;
      final ok = await confirmCandidate(candidate);
      if (!ok) break;
    }
  }

  Future<bool> confirmCandidate(
    CashbookCandidateTransaction candidate,
  ) async {
    try {
      final currentLedger = await _container.read(currentLedgerProvider.future);
      if (currentLedger == null) return false;

      final repo = _container.read(repositoryProvider);
      final note = _buildNote(candidate);

      final txId = await repo.addTransaction(
        ledgerId: currentLedger.id,
        type: candidate.direction == CashbookCandidateDirection.income
            ? 'income'
            : 'expense',
        amount: candidate.amount.abs(),
        happenedAt: candidate.occurredAt,
        note: note,
      );

      await TxAuthorService.markCreatedC(_container, txId);

      await PostProcessor.runC(
        _container,
        ledgerId: currentLedger.id,
      );

      await _markProcessed(candidate);
      logger.info(
        'CashbookCapture',
        '结构化通知候选已记账: source=${candidate.paymentLabel}, '
            'confidence=${candidate.confidence.toStringAsFixed(2)}',
      );
      return true;
    } catch (e, st) {
      logger.error(
        'CashbookCapture',
        '候选交易写入失败（候选保留）',
        e,
        st,
      );
      return false;
    }
  }

  Future<void> rejectCandidate(
    CashbookCandidateTransaction candidate,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = _loadPending(prefs)
      ..removeWhere((item) =>
          item.fingerprint == candidate.fingerprint &&
          item.occurredAt == candidate.occurredAt);
    await _savePending(prefs, pending);
    await _rememberProcessed(prefs, candidate.fingerprint);
  }

  String _buildNote(CashbookCandidateTransaction candidate) {
    final merchant = candidate.merchant?.trim();
    if (merchant == null || merchant.isEmpty) {
      return '${candidate.paymentLabel}自动识别';
    }
    return merchant;
  }

  Future<void> _markProcessed(
    CashbookCandidateTransaction candidate,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = _loadPending(prefs)
      ..removeWhere((item) =>
          item.fingerprint == candidate.fingerprint &&
          item.occurredAt == candidate.occurredAt);
    await _savePending(prefs, pending);
    await _rememberProcessed(prefs, candidate.fingerprint);
  }

  Future<void> _rememberProcessed(
    SharedPreferences prefs,
    String fingerprint,
  ) async {
    final processed = _loadProcessed(prefs);
    processed.remove(fingerprint);
    processed.add(fingerprint);
    if (processed.length > _maxProcessed) {
      processed.removeRange(0, processed.length - _maxProcessed);
    }
    await prefs.setStringList(_processedKey, processed);
  }

  List<CashbookCandidateTransaction> _loadPending(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return <CashbookCandidateTransaction>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CashbookCandidateTransaction>[];
      return decoded
          .whereType<Map>()
          .map((item) => CashbookCandidateTransaction.fromJson(
                item.cast<String, dynamic>(),
              ))
          .toList();
    } catch (_) {
      return <CashbookCandidateTransaction>[];
    }
  }

  Future<void> _savePending(
    SharedPreferences prefs,
    List<CashbookCandidateTransaction> items,
  ) async {
    await prefs.setString(
      _pendingKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  List<String> _loadProcessed(SharedPreferences prefs) =>
      prefs.getStringList(_processedKey)?.toList() ?? <String>[];
}
