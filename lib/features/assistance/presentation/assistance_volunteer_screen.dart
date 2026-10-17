import 'package:flutter/material.dart';

import '../../auth/application/resident_session.dart';
import '../application/assistance_volunteer_boundary.dart';

/// Private, voluntary resident opt-in and assignment response screen.
final class AssistanceVolunteerScreen extends StatefulWidget {
  const AssistanceVolunteerScreen({
    required this.session,
    required this.controller,
    super.key,
  });

  final ResidentSession session;
  final AssistanceVolunteerController controller;

  @override
  State<AssistanceVolunteerScreen> createState() =>
      _AssistanceVolunteerScreenState();
}

final class _AssistanceVolunteerScreenState
    extends State<AssistanceVolunteerScreen> {
  late Future<ResidentVolunteerData> _future;
  bool? _pendingWillingToHelp;
  bool _consentConfirmed = false;

  @override
  void initState() {
    super.initState();
    _future = widget.session.isOfflineSnapshot
        ? Future.error(StateError('Resident session is offline.'))
        : widget.controller.getVolunteerData();
  }

  void _reload() {
    setState(() {
      _future = widget.session.isOfflineSnapshot
          ? Future.error(StateError('Resident session is offline.'))
          : widget.controller.getVolunteerData();
      _pendingWillingToHelp = null;
      _consentConfirmed = false;
    });
  }

  Future<void> _saveConsent() async {
    final willing = _pendingWillingToHelp;
    if (willing == null ||
        !_consentConfirmed ||
        widget.session.isOfflineSnapshot) {
      return;
    }
    try {
      await widget.controller.updateVolunteerConsent(willingToHelp: willing);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            willing
                ? 'Kesediaan membantu tersimpan. Anda bebas menolak permintaan.'
                : 'Kesediaan membantu dinonaktifkan.',
          ),
        ),
      );
      _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilihan belum tersimpan. Coba lagi.')),
        );
      }
    }
  }

  Future<void> _respond(
    HelperAssignmentRecord assignment,
    String decision,
  ) async {
    final action = switch (decision) {
      'ACCEPTED' => 'menerima',
      'DECLINED' => 'menolak',
      _ => 'mengundurkan diri dari',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Konfirmasi $action permintaan?'),
        content: const Text(
          'Pilihan ini sukarela dan tanpa penalti. Anda dapat menolak atau '
          'mengundurkan diri kapan saja. Aplikasi tidak menampilkan identitas '
          'rumah tangga.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: Key('helper-decision-confirm-$decision'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(switch (decision) {
              'ACCEPTED' => 'Terima',
              'DECLINED' => 'Tolak',
              _ => 'Mengundurkan diri',
            }),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.respondToHelperAssignment(
        assignmentId: assignment.assignmentId,
        decision: decision,
      );
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pilihan relawan belum tersimpan. Coba lagi.'),
          ),
        );
      }
    }
  }

  Widget _buildContent(ResidentVolunteerData data) {
    final willing = _pendingWillingToHelp ?? data.willingToHelp;
    final canEdit = !widget.session.isOfflineSnapshot;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${widget.session.rtLabel} · Warga',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.volunteer_activism_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Partisipasi Sukarela',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Menjadi relawan sepenuhnya sukarela. Anda dapat menolak setiap '
                  'permintaan atau mengundurkan diri tanpa penalti. Guyub.id tidak '
                  'menampilkan identitas rumah tangga.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Koordinasikan arahan aman dengan Pendamping RT. '
                          'Jangan memasuki saluran atau aliran berbahaya.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.session.isOfflineSnapshot) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Mode offline. Kesediaan dan permintaan bantuan belum '
                    'diperbarui dari server.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  key: const Key('helper-willingness-toggle'),
                  contentPadding: EdgeInsets.zero,
                  value: willing,
                  onChanged: canEdit
                      ? (value) => setState(() {
                          _pendingWillingToHelp = value;
                          _consentConfirmed = false;
                        })
                      : null,
                  title: Text(
                    'Saya bersedia membantu secara sukarela',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'RT hanya dapat mengirim permintaan setelah Anda setuju.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_pendingWillingToHelp != null) ...[
                  const Divider(height: 24),
                  CheckboxListTile(
                    key: const Key('helper-consent-confirm'),
                    contentPadding: EdgeInsets.zero,
                    value: _consentConfirmed,
                    onChanged: canEdit
                        ? (value) =>
                              setState(() => _consentConfirmed = value ?? false)
                        : null,
                    title: Text(
                      'Saya mengonfirmasi pilihan ini tanpa tekanan.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('helper-consent-save'),
                    onPressed: canEdit && _consentConfirmed
                        ? _saveConsent
                        : null,
                    icon: Icon(
                      _pendingWillingToHelp == true
                          ? Icons.check_circle_outline
                          : Icons.block_outlined,
                    ),
                    label: Text(
                      _pendingWillingToHelp == true
                          ? 'Simpan kesediaan'
                          : 'Nonaktifkan kesediaan',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Permintaan bantuan',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (data.isPartial)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Dibatasi 200',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (data.assignments.isEmpty)
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada permintaan bantuan',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'RT akan mengirim permintaan bantuan jika Anda sudah menyatakan kesediaan.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (final assignment in data.assignments)
            Card(
              key: ValueKey('helper-assignment-${assignment.assignmentId}'),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: assignment.state == 'OFFERED'
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                      .colorScheme
                                      .tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            assignment.state == 'OFFERED'
                                ? Icons.help_outline
                                : Icons.handshake_outlined,
                            color: assignment.state == 'OFFERED'
                                ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                : Theme.of(context)
                                      .colorScheme
                                      .onTertiaryContainer,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            assignment.state == 'OFFERED'
                                ? 'Permintaan menunggu pilihan Anda'
                                : 'Anda menerima permintaan bantuan',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Detail rumah tangga tidak ditampilkan. Hubungi Pendamping RT '
                      'setelah memilih untuk koordinasi yang aman.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (assignment.state == 'OFFERED')
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: Key(
                                'helper-decline-${assignment.assignmentId}',
                              ),
                              onPressed: canEdit
                                  ? () => _respond(assignment, 'DECLINED')
                                  : null,
                              icon: const Icon(Icons.close),
                              label: const Text('Tolak'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              key: Key(
                                'helper-accept-${assignment.assignmentId}',
                              ),
                              onPressed: canEdit
                                  ? () => _respond(assignment, 'ACCEPTED')
                                  : null,
                              icon: const Icon(Icons.check),
                              label: const Text('Terima'),
                            ),
                          ),
                        ],
                      )
                    else
                      OutlinedButton.icon(
                        key: Key('helper-withdraw-${assignment.assignmentId}'),
                        onPressed: canEdit
                            ? () => _respond(assignment, 'WITHDRAWN')
                            : null,
                        icon: const Icon(Icons.exit_to_app),
                        label: const Text('Mengundurkan diri'),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kesediaan Membantu')),
    body: FutureBuilder<ResidentVolunteerData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.session.isOfflineSnapshot
                      ? 'Mode offline. Kesediaan relawan belum diperbarui dari server.'
                      : 'Status relawan belum dapat dimuat.',
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('helper-retry'),
                  onPressed: _reload,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: _buildContent(snapshot.data!),
        );
      },
    ),
  );
}
