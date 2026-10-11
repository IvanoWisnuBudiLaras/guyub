import 'package:flutter/material.dart';

import '../../auth/application/operator_profile.dart';
import '../../tasks/application/task_campaign_boundary.dart';
import '../../tasks/application/task_location_reference.dart';
import '../../tasks/application/task_template.dart';
import '../../tasks/presentation/screens/task_campaign_confirmation_screen.dart';
import '../application/resident_proposal_boundary.dart';

/// Same-RT proposal review queue. Review can close a proposal but cannot create a task.
final class ResidentProposalReviewScreen extends StatefulWidget {
  const ResidentProposalReviewScreen({
    required this.profile,
    required this.controller,
    this.campaignController,
    super.key,
  });

  final OperatorProfile profile;
  final ResidentProposalReviewController controller;
  final TaskCampaignController? campaignController;

  @override
  State<ResidentProposalReviewScreen> createState() =>
      _ResidentProposalReviewScreenState();
}

final class _ResidentProposalReviewScreenState
    extends State<ResidentProposalReviewScreen> {
  late Future<ResidentProposalQueue> _queue;
  final Set<String> _busyIds = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _queue = widget.controller.list();
  }

  Future<void> _refresh() async {
    final pending = widget.controller.list();
    setState(() {
      _error = null;
      _queue = pending;
    });
    await pending;
  }

  Future<void> _dismiss(ResidentProposalRecord proposal) async {
    setState(() {
      _busyIds.add(proposal.proposalId);
      _error = null;
    });
    try {
      await widget.controller.dismiss(proposal.proposalId);
      if (!mounted) return;
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Usulan belum dapat diperbarui. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(proposal.proposalId));
    }
  }

  Future<void> _markNeedsOfficialReport(ResidentProposalRecord proposal) async {
    setState(() {
      _busyIds.add(proposal.proposalId);
      _error = null;
    });
    try {
      await widget.controller.markNeedsOfficialReport(proposal.proposalId);
      if (!mounted) return;
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Usulan belum dapat diperbarui. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(proposal.proposalId));
    }
  }

  Future<void> _mapToDraft(ResidentProposalRecord proposal) async {
    final campaignController = widget.campaignController;
    if (campaignController == null) return;
    setState(() {
      _busyIds.add(proposal.proposalId);
      _error = null;
    });
    try {
      final templates = await campaignController.listApprovedTemplates();
      if (!mounted) return;
      if (templates.isEmpty) {
        setState(
          () => _error = 'Belum ada template tugas aman yang disetujui.',
        );
        return;
      }
      final selection = await showDialog<_ProposalDraftSelection>(
        context: context,
        builder: (_) =>
            _MapProposalDialog(proposal: proposal, templates: templates),
      );
      if (selection == null || !mounted) return;
      final mapping = await widget.controller.mapToDraft(
        proposalId: proposal.proposalId,
        template: selection.template,
        deadline: selection.deadline,
        locationReference: selection.locationReference,
      );
      if (!mounted) return;
      setState(() {
        _queue = widget.controller.list();
      });
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TaskCampaignConfirmationScreen(
            profile: widget.profile,
            campaign: mapping.campaign,
            controller: campaignController,
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _queue = widget.controller.list();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Draf belum dapat dibuat. Periksa koneksi dan akses RT, lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(proposal.proposalId));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tinjau Usulan Warga')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${widget.profile.role.label} · RT ${widget.profile.communityId}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Usulan bukan tugas aktif. RT hanya dapat memilih template aman untuk membuat draf. Teks usulan tidak menjadi instruksi, dan aktivasi memerlukan konfirmasi operator terpisah.',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: FutureBuilder<ResidentProposalQueue>(
            future: _queue,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 100),
                      Center(
                        child: Text(
                          'Usulan belum dapat dimuat. Tarik untuk mencoba lagi.',
                        ),
                      ),
                    ],
                  ),
                );
              }
              final queue = snapshot.data!;
              if (queue.items.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text('Tidak ada usulan yang menunggu tinjauan.'),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (queue.isPartial)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Daftar menampilkan hingga 100 usulan. Setelah ada yang ditutup, tarik untuk memuat usulan berikutnya.',
                        ),
                      ),
                    for (final proposal in queue.items)
                      _ProposalCard(
                        proposal: proposal,
                        busy: _busyIds.contains(proposal.proposalId),
                        onDismiss: proposal.state == 'SUBMITTED'
                            ? () => _dismiss(proposal)
                            : null,
                        onOfficialReport: proposal.state == 'SUBMITTED'
                            ? () => _markNeedsOfficialReport(proposal)
                            : null,
                        onMap:
                            proposal.state == 'SUBMITTED' &&
                                widget.campaignController != null
                            ? () => _mapToDraft(proposal)
                            : null,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

final class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.busy,
    required this.onDismiss,
    required this.onMap,
    this.onOfficialReport,
  });

  final ResidentProposalRecord proposal;
  final bool busy;
  final VoidCallback? onDismiss;
  final VoidCallback? onMap;
  final VoidCallback? onOfficialReport;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(proposal.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('Dari: ${proposal.submitterNickname ?? 'Warga'}'),
          Text('Kategori: ${proposal.category.label}'),
          if (proposal.locationReference case final location?)
            Text(
              'Jenis lokasi umum: ${TaskLocationReferences.label(location)}',
            ),
          const SizedBox(height: 8),
          Text(proposal.description),
          const SizedBox(height: 8),
          Text(
            proposal.state == 'SUBMITTED'
                ? 'Menunggu tinjauan RT'
                : proposal.state == 'NEEDS_OFFICIAL_REPORT'
                ? 'Perlu penanganan kanal resmi'
                : 'Usulan ditutup',
          ),
          if (onMap != null ||
              onDismiss != null ||
              onOfficialReport != null) ...[
            const SizedBox(height: 8),
            if (onMap != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: Key('proposal-map-${proposal.proposalId}'),
                  onPressed: busy ? null : onMap,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Pilih template aman untuk draf'),
                ),
              ),
            if (onOfficialReport != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('proposal-official-${proposal.proposalId}'),
                  onPressed: busy ? null : onOfficialReport,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.outbond_outlined),
                  label: const Text('Arahkan ke kanal resmi'),
                ),
              ),
            if (onDismiss != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: Key('proposal-dismiss-${proposal.proposalId}'),
                  onPressed: busy ? null : onDismiss,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.archive_outlined),
                  label: const Text('Tutup usulan'),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

final class _ProposalDraftSelection {
  const _ProposalDraftSelection(
    this.template,
    this.deadline,
    this.locationReference,
  );
  final TaskTemplate template;
  final DateTime deadline;
  final String? locationReference;
}

final class _MapProposalDialog extends StatefulWidget {
  const _MapProposalDialog({required this.proposal, required this.templates});
  final ResidentProposalRecord proposal;
  final List<TaskTemplate> templates;
  @override
  State<_MapProposalDialog> createState() => _MapProposalDialogState();
}

final class _MapProposalDialogState extends State<_MapProposalDialog> {
  static const _none = '__none__';
  TaskTemplate? _template;
  DateTime? _deadline;
  String? _location;
  bool get _valid =>
      _template != null &&
      _deadline != null &&
      _deadline!.isAfter(DateTime.now()) &&
      _location != null;

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
    );
    if (!mounted || time == null) return;
    setState(
      () => _deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pilih template aman untuk draf'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Konteks usulan warga — bukan instruksi tugas. Isi usulan tidak disalin ke draf.',
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.proposal.title),
                    const SizedBox(height: 4),
                    Text(widget.proposal.description),
                  ],
                ),
              ),
            ),
            DropdownButtonFormField<TaskTemplate>(
              key: const Key('proposal-map-template'),
              initialValue: _template,
              decoration: const InputDecoration(
                labelText: 'Template aman yang disetujui',
              ),
              items: [
                for (final t in widget.templates)
                  DropdownMenuItem(value: t, child: Text(t.title)),
              ],
              onChanged: (value) => setState(() => _template = value),
            ),
            if (_template case final t?) ...[
              Text('Instruksi template: ${t.coreInstruction}'),
              // [usulan-draf:instruksi-keselamatan]: Instruksi keselamatan ditebalkan agar menonjol sebelum aktivasi draf.
              Text(
                'Instruksi keselamatan: ${t.safetyInstruction}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            DropdownButtonFormField<String>(
              key: const Key('proposal-map-location'),
              initialValue: _location,
              decoration: const InputDecoration(labelText: 'Lokasi umum tugas'),
              items: [
                const DropdownMenuItem(
                  value: _none,
                  child: Text('Tanpa lokasi khusus'),
                ),
                for (final loc in TaskLocationReferences.allowed)
                  DropdownMenuItem(
                    value: loc,
                    child: Text(TaskLocationReferences.label(loc)),
                  ),
              ],
              onChanged: (value) => setState(() => _location = value),
            ),
            OutlinedButton.icon(
              key: const Key('proposal-map-deadline'),
              onPressed: _pickDeadline,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                _deadline == null
                    ? 'Pilih tenggat tanggal dan waktu'
                    : 'Tenggat: ${_deadline!.toLocal()}',
              ),
            ),
            const Text(
              'Draf memakai instruksi template terkunci. Aktivasi memerlukan konfirmasi operator terpisah.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        key: const Key('proposal-map-create-draft'),
        onPressed: _valid
            ? () => Navigator.pop(
                context,
                _ProposalDraftSelection(
                  _template!,
                  _deadline!,
                  _location == _none ? null : _location,
                ),
              )
            : null,
        child: const Text('Buat draf'),
      ),
    ],
  );
}
