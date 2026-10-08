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
        Text('${widget.session.rtLabel} · Warga'),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Menjadi relawan sepenuhnya sukarela. Anda dapat menolak setiap '
              'permintaan atau mengundurkan diri tanpa penalti. Guyub.id tidak '
              'menampilkan identitas rumah tangga. Koordinasikan arahan aman '
              'dengan Pendamping RT; jangan memasuki saluran atau aliran berbahaya.',
            ),
          ),
        ),
        if (widget.session.isOfflineSnapshot) ...[
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Mode offline. Kesediaan dan permintaan bantuan belum '
                'diperbarui dari server.',
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
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
                  title: const Text('Saya bersedia membantu secara sukarela'),
                  subtitle: const Text(
                    'RT hanya dapat mengirim permintaan setelah Anda setuju.',
                  ),
                ),
                if (_pendingWillingToHelp != null) ...[
                  CheckboxListTile(
                    key: const Key('helper-consent-confirm'),
                    contentPadding: EdgeInsets.zero,
                    value: _consentConfirmed,
                    onChanged: canEdit
                        ? (value) =>
                              setState(() => _consentConfirmed = value ?? false)
                        : null,
                    title: const Text(
                      'Saya mengonfirmasi pilihan ini tanpa tekanan.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  FilledButton(
                    key: const Key('helper-consent-save'),
                    onPressed: canEdit && _consentConfirmed
                        ? _saveConsent
                        : null,
                    child: Text(
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
        const SizedBox(height: 16),
        Text(
          'Permintaan bantuan',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (data.isPartial)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Daftar dibatasi hingga 200 permintaan.'),
          ),
        if (data.assignments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Belum ada permintaan bantuan dari RT.'),
          )
        else
          for (final assignment in data.assignments)
            Card(
              key: ValueKey('helper-assignment-${assignment.assignmentId}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      assignment.state == 'OFFERED'
                          ? 'Permintaan menunggu pilihan Anda'
                          : 'Anda menerima permintaan bantuan',
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Detail rumah tangga tidak ditampilkan. Hubungi Pendamping RT '
                      'setelah memilih untuk koordinasi yang aman.',
                    ),
                    const SizedBox(height: 8),
                    if (assignment.state == 'OFFERED')
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            key: Key(
                              'helper-decline-${assignment.assignmentId}',
                            ),
                            onPressed: canEdit
                                ? () => _respond(assignment, 'DECLINED')
                                : null,
                            child: const Text('Tolak'),
                          ),
                          FilledButton(
                            key: Key(
                              'helper-accept-${assignment.assignmentId}',
                            ),
                            onPressed: canEdit
                                ? () => _respond(assignment, 'ACCEPTED')
                                : null,
                            child: const Text('Terima'),
                          ),
                        ],
                      )
                    else
                      OutlinedButton(
                        key: Key('helper-withdraw-${assignment.assignmentId}'),
                        onPressed: canEdit
                            ? () => _respond(assignment, 'WITHDRAWN')
                            : null,
                        child: const Text('Mengundurkan diri'),
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
