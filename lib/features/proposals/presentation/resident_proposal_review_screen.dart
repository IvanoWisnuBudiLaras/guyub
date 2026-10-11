import 'package:flutter/material.dart';

import '../../auth/application/operator_profile.dart';
import '../../tasks/application/task_location_reference.dart';
import '../application/resident_proposal_boundary.dart';

/// Same-RT proposal review queue. Review can close a proposal but cannot create a task.
final class ResidentProposalReviewScreen extends StatefulWidget {
  const ResidentProposalReviewScreen({
    required this.profile,
    required this.controller,
    super.key,
  });

  final OperatorProfile profile;
  final ResidentProposalReviewController controller;

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
            'Usulan bukan tugas aktif. Menutup usulan tidak mengaktifkan atau mengirim tugas.',
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
    this.onOfficialReport,
  });

  final ResidentProposalRecord proposal;
  final bool busy;
  final VoidCallback? onDismiss;
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
          if (onDismiss != null || onOfficialReport != null) ...[
            const SizedBox(height: 8),
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
