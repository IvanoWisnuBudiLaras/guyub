import 'package:flutter/material.dart';

import '../../auth/application/operator_profile.dart';
import '../../auth/application/resident_session.dart';
import '../application/task_push_notifications.dart';

/// Explicit, reversible push opt-in. Opening a dashboard never requests permission.
final class TaskPushOptInCard extends StatefulWidget {
  const TaskPushOptInCard.forResident({
    required this.controller,
    required this.session,
    super.key,
  }) : profile = null;

  const TaskPushOptInCard.forPendamping({
    required this.controller,
    required this.profile,
    super.key,
  }) : session = null;

  final TaskPushNotificationsController controller;
  final ResidentSession? session;
  final OperatorProfile? profile;

  TaskPushAudience get _audience =>
      session != null ? TaskPushAudience.resident : TaskPushAudience.pendamping;

  String get _identityId => session?.residentId ?? profile!.uid;

  @override
  State<TaskPushOptInCard> createState() => _TaskPushOptInCardState();
}

final class _TaskPushOptInCardState extends State<TaskPushOptInCard> {
  late Future<bool> _preference;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _preference = widget.controller.isEnabled(
      widget._audience,
      identityId: widget._identityId,
    );
  }

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = widget.session != null
          ? await widget.controller.enableResident(widget.session!)
          : await widget.controller.enablePendamping(widget.profile!);
      if (!mounted) return;
      final message = switch (result) {
        TaskPushOptInResult.enabled => 'Pilihan notifikasi tersimpan. Push hanya pemberitahuan tambahan; periksa status tugas di aplikasi.',
        TaskPushOptInResult.permissionDenied => 'Izin notifikasi tidak diberikan. Tugas tetap dapat dibuka di aplikasi.',
        TaskPushOptInResult.unavailable => 'Pendaftaran notifikasi belum dapat dipastikan. Tugas tetap dapat dibuka di aplikasi.',
      };
      _showMessage(message);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Notifikasi belum dapat diatur. Tugas tetap tersedia di aplikasi.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _preference = widget.controller.isEnabled(
            widget._audience,
            identityId: widget._identityId,
          );
        });
      }
    }
  }

  Future<void> _disable() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (widget.session != null) {
        await widget.controller.disableResident(widget.session!);
      } else {
        await widget.controller.disablePendamping(widget.profile!);
      }
      if (mounted) _showMessage('Pemberitahuan push dimatikan untuk sesi ini.');
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Belum dapat membatalkan pendaftaran notifikasi. Coba lagi saat tersambung.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _preference = widget.controller.isEnabled(
            widget._audience,
            identityId: widget._identityId,
          );
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.notifications_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifikasi Push',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    FutureBuilder<bool>(
                      future: _preference,
                      builder: (context, snapshot) => Text(
                        snapshot.data == true ? 'Aktif' : 'Nonaktif',
                        key: const Key('task-push-preference-status'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Pemberitahuan dapat terlambat atau tidak terkirim. '
            'Periksa status terbaru di aplikasi.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('disable-task-push-notifications'),
                  onPressed: _busy ? null : _disable,
                  icon: const Icon(Icons.notifications_off_outlined, size: 18),
                  label: const Text('Matikan'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('enable-task-push-notifications'),
                  onPressed: _busy ? null : _enable,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.notifications_active_outlined,
                          size: 18,
                        ),
                  label: Text(_busy ? 'Proses…' : 'Aktifkan'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
