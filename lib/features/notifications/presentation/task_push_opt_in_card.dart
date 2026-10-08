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
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Notifikasi push opsional',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Pemberitahuan dapat terlambat atau tidak terkirim. Periksa status terbaru di aplikasi; keikutsertaan tugas tetap sukarela.',
          ),
          const SizedBox(height: 8),
          FutureBuilder<bool>(
            future: _preference,
            builder: (context, snapshot) => Text(
              'Preferensi aplikasi: ${snapshot.data == true ? 'aktif' : 'nonaktif'}',
              key: const Key('task-push-preference-status'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('enable-task-push-notifications'),
            onPressed: _busy ? null : _enable,
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(_busy ? 'Memproses…' : 'Aktifkan atau sinkronkan'),
          ),
          TextButton.icon(
            key: const Key('disable-task-push-notifications'),
            onPressed: _busy ? null : _disable,
            icon: const Icon(Icons.notifications_off_outlined),
            label: const Text('Matikan notifikasi'),
          ),
        ],
      ),
    ),
  );
}
