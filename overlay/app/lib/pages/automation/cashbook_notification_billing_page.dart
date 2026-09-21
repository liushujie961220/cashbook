import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/automation/cashbook_notification_capture_service.dart';
import '../../widgets/ui/primary_header.dart';

class CashbookNotificationBillingPage extends StatefulWidget {
  const CashbookNotificationBillingPage({super.key});

  @override
  State<CashbookNotificationBillingPage> createState() =>
      _CashbookNotificationBillingPageState();
}

class _CashbookNotificationBillingPageState
    extends State<CashbookNotificationBillingPage>
    with WidgetsBindingObserver {
  CashbookNotificationCaptureService? _service;
  bool _loading = true;
  bool _notificationAccess = false;
  bool _autoConfirm = false;
  double _threshold =
      CashbookNotificationCaptureService.defaultAutoConfirmThreshold;
  List<CashbookCandidateTransaction> _pending = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service == null) {
      final container = ProviderScope.containerOf(context);
      _service = CashbookNotificationCaptureService(container);
      _reload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _reload() async {
    final service = _service;
    if (service == null) return;

    setState(() => _loading = true);
    await service.refreshCandidates();

    final access = await service.isNotificationAccessGranted();
    final autoConfirm = await service.isAutoConfirmEnabled();
    final threshold = await service.autoConfirmThreshold();
    final pending = await service.pendingCandidates();

    if (!mounted) return;
    setState(() {
      _notificationAccess = access;
      _autoConfirm = autoConfirm;
      _threshold = threshold;
      _pending = pending.reversed.toList(growable: false);
      _loading = false;
    });
  }

  Future<void> _toggleAutoConfirm(bool value) async {
    final service = _service;
    if (service == null) return;
    await service.setAutoConfirmEnabled(value);
    await _reload();
  }

  Future<void> _setThreshold(double value) async {
    final service = _service;
    if (service == null) return;
    setState(() => _threshold = value);
    await service.setAutoConfirmThreshold(value);
  }

  Future<void> _confirm(CashbookCandidateTransaction candidate) async {
    final service = _service;
    if (service == null) return;
    final ok = await service.confirmCandidate(candidate);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已记入当前账本' : '当前账本尚未就绪，候选已保留'),
      ),
    );
    await _reload();
  }

  Future<void> _reject(CashbookCandidateTransaction candidate) async {
    final service = _service;
    if (service == null) return;
    await service.rejectCandidate(candidate);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          const PrimaryHeader(
            title: '支付通知自动记账',
            showBack: true,
            leadingIcon: Icons.receipt_long,
            leadingPlain: true,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _privacyCard(context),
                  const SizedBox(height: 12),
                  _permissionCard(context),
                  const SizedBox(height: 12),
                  _automationCard(context),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        '待确认',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_pending.length} 笔',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_pending.isEmpty)
                    _emptyCard(context)
                  else
                    ..._pending.map(
                      (candidate) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _candidateCard(context, candidate),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _privacyCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.privacy_tip_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Cashbook 只在本机读取微信/支付宝通知并立即过滤。'
                '原始通知不保存、不上传；进入这里的只有金额、收支方向、'
                '商户候选、时间、来源和置信度。',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionCard(BuildContext context) {
    final color = _notificationAccess ? Colors.green : Colors.orange;

    return Card(
      child: ListTile(
        leading: Icon(
          _notificationAccess
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          color: color,
        ),
        title: const Text('通知访问权限'),
        subtitle: Text(_notificationAccess ? '已开启' : '未开启，无法自动识别支付通知'),
        trailing: FilledButton.tonal(
          onPressed: () async {
            await _service?.openNotificationAccessSettings();
          },
          child: Text(_notificationAccess ? '系统设置' : '去开启'),
        ),
      ),
    );
  }

  Widget _automationCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('高置信度自动入账'),
              subtitle: const Text('默认关闭。建议先观察真实通知识别效果后再开启。'),
              value: _autoConfirm,
              onChanged: _notificationAccess ? _toggleAutoConfirm : null,
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('自动入账阈值')),
                Text(
                  _threshold.toStringAsFixed(2),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            Slider(
              value: _threshold.clamp(0.80, 0.99).toDouble(),
              min: 0.80,
              max: 0.99,
              divisions: 19,
              label: _threshold.toStringAsFixed(2),
              onChanged: _autoConfirm ? _setThreshold : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 10),
            const Text('暂无待确认交易'),
            const SizedBox(height: 4),
            Text(
              '完成一笔微信或支付宝支付后，下拉刷新即可检查。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidateCard(
    BuildContext context,
    CashbookCandidateTransaction candidate,
  ) {
    final theme = Theme.of(context);
    final income = candidate.direction == CashbookCandidateDirection.income;
    final sign = income ? '+' : '-';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    candidate.merchant ?? '${candidate.paymentLabel}交易',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$sign¥${candidate.amount.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: income ? Colors.green : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${candidate.paymentLabel} · '
              '置信度 ${candidate.confidence.toStringAsFixed(2)} · '
              '${_formatTime(candidate.occurredAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _reject(candidate),
                  child: const Text('忽略'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _confirm(candidate),
                  child: const Text('确认入账'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
