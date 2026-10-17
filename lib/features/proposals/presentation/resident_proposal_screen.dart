import 'package:flutter/material.dart';

import '../../../../app/router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
import '../../../../core/widgets/tinted_info_box.dart';
import '../../auth/application/resident_session.dart';
import '../../tasks/application/task_location_reference.dart';
import '../application/resident_proposal_boundary.dart';

/// Resident proposal screen.
///
/// Menyediakan dua tab:
/// 1. "Ajukan Usulan": Formulir pembuatan usulan persiapan gotong royong warga.
/// 2. "Usulan Saya": Riwayat usulan beserta status tindak lanjut dari pengurus RT.
final class ResidentProposalScreen extends StatefulWidget {
  const ResidentProposalScreen({
    required this.session,
    required this.controller,
    super.key,
  });

  final ResidentSession session;
  final ResidentProposalController controller;

  @override
  State<ResidentProposalScreen> createState() => _ResidentProposalScreenState();
}

final class _ResidentProposalScreenState extends State<ResidentProposalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  ResidentProposalCategory _category =
      ResidentProposalCategory.householdPreparation;
  String? _locationReference;
  ResidentProposalRecord? _submitted;
  String? _error;
  bool _saving = false;

  late Future<List<ResidentProposalRecord>> _myProposalsFuture;

  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != _selectedTab) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
    _reloadMyProposals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _reloadMyProposals() {
    setState(() {
      _myProposalsFuture = widget.controller.listMyProposals();
    });
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (title.isEmpty || description.isEmpty) {
      setState(() => _error = 'Isi judul dan penjelasan usulan.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = await widget.controller.submit(
        residentId: widget.session.residentId,
        communityId: widget.session.communityId,
        title: title,
        description: description,
        category: _category,
        locationReference: _locationReference,
      );
      if (mounted) {
        setState(() => _submitted = record);
        _reloadMyProposals();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Usulan belum dapat dikirim. Periksa koneksi, lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usulan Persiapan Warga'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ajukan Usulan'),
            Tab(text: 'Usulan Saya'),
          ],
        ),
      ),
      body: _selectedTab == 0
          ? _buildSubmissionForm(context)
          : _buildMyProposalsList(context),
    );
  }

  Widget _buildSubmissionForm(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Warga • ${widget.session.rtLabel}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        const TintedInfoBox(
          tint: TintType.info,
          icon: Icons.info_outline,
          child: Text(
            'Usulan tidak otomatis menjadi tugas aktif. RT akan meninjau terlebih dahulu untuk memastikan keselamatan dan kapasitas gotong royong warga.',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('proposal-title'),
          controller: _titleController,
          enabled: !_saving && _submitted == null,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Judul usulan',
            hintText: 'Contoh: Bersihkan saluran air depan pos',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('proposal-description'),
          controller: _descriptionController,
          enabled: !_saving && _submitted == null,
          maxLength: 1000,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Penjelasan singkat',
            hintText: 'Jelaskan kondisi dan rencana persiapan...',
            helperText:
                'Jangan masukkan NIK, nomor telepon, alamat, atau koordinat GPS.',
            helperMaxLines: 4,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ResidentProposalCategory>(
          key: const Key('proposal-category'),
          isExpanded: true,
          initialValue: _category,
          decoration: const InputDecoration(
            labelText: 'Kategori usulan',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final category in ResidentProposalCategory.values)
              DropdownMenuItem(value: category, child: Text(category.label)),
          ],
          onChanged: _saving || _submitted != null
              ? null
              : (category) {
                  if (category != null) setState(() => _category = category);
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('proposal-location'),
          isExpanded: true,
          initialValue: _locationReference,
          decoration: const InputDecoration(
            labelText: 'Jenis lokasi umum (opsional)',
            helperText: 'Pilih jenis area, bukan alamat rumah.',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final location in TaskLocationReferences.allowed)
              DropdownMenuItem(
                value: location,
                child: Text(TaskLocationReferences.label(location)),
              ),
          ],
          onChanged: _saving || _submitted != null
              ? null
              : (location) => setState(() => _locationReference = location),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          TintedInfoBox.danger(text: _error!),
        ],
        if (_submitted case final submitted?) ...[
          const SizedBox(height: 16),
          TintedInfoBox(
            key: const Key('proposal-submitted'),
            tint: submitted.state == 'SUBMITTED'
                ? TintType.warning
                : TintType.info,
            icon: submitted.state == 'SUBMITTED'
                ? Icons.schedule_outlined
                : Icons.visibility_outlined,
            title: submitted.state == 'SUBMITTED'
                ? 'Menunggu Tinjauan RT'
                : 'Usulan telah ditinjau RT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Usulan ini belum menjadi tugas aktif. Menunggu peninjauan dan aktivasi oleh pengurus RT.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Usulan: ${submitted.title}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    _tabController.animateTo(1);
                  },
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Lihat di Tab Usulan Saya'),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('proposal-submit'),
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: const Text('Kirim Usulan ke RT'),
          ),
        ],
      ],
    );
  }

  Widget _buildMyProposalsList(BuildContext context) {
    final colors = context.appColors;

    return FutureBuilder<List<ResidentProposalRecord>>(
      future: _myProposalsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Riwayat usulan belum dapat dimuat. Coba lagi saat tersambung.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _reloadMyProposals,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          );
        }

        final proposals = snapshot.data ?? const <ResidentProposalRecord>[];
        if (proposals.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => _reloadMyProposals(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(32),
              children: [
                const SizedBox(height: 60),
                Icon(
                  Icons.lightbulb_outline,
                  size: 56,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Belum ada usulan yang diajukan',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Usulan persiapan gotong royong yang Anda kirim akan muncul di sini beserta status peninjauannya dari RT.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
                const SizedBox(height: 24),
                Center(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _tabController.animateTo(0),
                    icon: const Icon(Icons.add),
                    label: const Text('Buat Usulan Baru'),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reloadMyProposals(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: proposals.length,
            itemBuilder: (context, index) {
              final proposal = proposals[index];
              return _ProposalStatusCard(
                proposal: proposal,
                onViewEmergencyChannels: () {
                  Navigator.of(context).pushNamed(
                    AppRouter.emergencyDirectory,
                    arguments: widget.session,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

final class _ProposalStatusCard extends StatelessWidget {
  const _ProposalStatusCard({
    required this.proposal,
    required this.onViewEmergencyChannels,
  });

  final ResidentProposalRecord proposal;
  final VoidCallback onViewEmergencyChannels;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final (String badgeLabel, Color badgeColor, Color badgeBg, IconData badgeIcon) =
        switch (proposal.state) {
      'SUBMITTED' => (
        'Menunggu Tinjauan RT',
        const Color(0xFFB45309),
        colors.warningBg,
        Icons.schedule,
      ),
      'NEEDS_OFFICIAL_REPORT' => (
        'Diarahkan ke Kanal Resmi',
        colors.primaryDark,
        colors.primarySoft,
        Icons.alt_route_rounded,
      ),
      'MAPPED_TO_SAFE_TEMPLATE' => (
        'Disetujui RT jadi Tugas',
        colors.success,
        colors.successBg,
        Icons.check_circle_outline,
      ),
      'DISMISSED' => (
        'Belum Dapat Dilaksanakan',
        colors.textSecondary,
        colors.background,
        Icons.cancel_outlined,
      ),
      _ => (
        'Dalam Proses',
        colors.textSecondary,
        colors.background,
        Icons.help_outline,
      ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    proposal.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 14, color: badgeColor),
                      const SizedBox(width: 4),
                      Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              proposal.description,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.label_outline, size: 14, color: colors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  proposal.category.label,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const Spacer(),
                Text(
                  IndonesianDateFormatter.formatDateOnly(proposal.submittedAt),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),

            // Panduan Khusus jika diarahkan ke Kanal Resmi Pemerintah
            if (proposal.state == 'NEEDS_OFFICIAL_REPORT') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: colors.primaryDark,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Arahan Pengurus RT',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: colors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'RT telah meninjau usulan ini dan menyarankan untuk dilaporkan ke kanal resmi pemerintah (misal: JAKI, Kelurahan, atau Call Center 112) karena membutuhkan tindakan teknis/wewenang dinas terkait di luar batas kapasitas gotong royong warga.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: onViewEmergencyChannels,
                      icon: const Icon(Icons.phone_in_talk_outlined, size: 16),
                      label: const Text('Buka Kontak & Kanal Resmi'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Keterangan jika Disetujui jadi Tugas Aktif
            if (proposal.state == 'MAPPED_TO_SAFE_TEMPLATE') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.successBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.task_alt, size: 16, color: colors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Usulan telah disetujui RT dan dijadikan tugas gotong royong warga.',
                        style: TextStyle(fontSize: 12, color: colors.success),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Keterangan jika Belum Dapat Dilaksanakan
            if (proposal.state == 'DISMISSED') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'RT telah meninjau usulan ini dan memutuskan belum dapat dilaksanakan saat ini.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
