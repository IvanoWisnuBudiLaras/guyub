import 'package:flutter/material.dart';

import '../../auth/application/operator_profile.dart';
import '../../tasks/application/task_campaign_boundary.dart';
import '../application/assistance_volunteer_boundary.dart';
import '../application/proxy_resident_boundary.dart';

/// RT-only list and proxy status workflow for residents without app access.
final class ProxyResidentScreen extends StatefulWidget {
  const ProxyResidentScreen({
    required this.profile,
    required this.controller,
    this.taskCampaignController,
    super.key,
  });

  final OperatorProfile profile;
  final ProxyResidentController controller;
  final TaskCampaignController? taskCampaignController;

  @override
  State<ProxyResidentScreen> createState() => _ProxyResidentScreenState();
}

final class _ProxyPageData {
  const _ProxyPageData({
    required this.residents,
    required this.isPartial,
    required this.helpers,
    required this.helperLoadFailed,
    required this.tasks,
  });
  final List<ProxyResidentRecord> residents;
  final bool isPartial;
  final VolunteerHelperList helpers;
  final bool helperLoadFailed;
  final List<ActiveTaskCampaignRecord> tasks;
}

final class _ProxyResidentScreenState extends State<ProxyResidentScreen> {
  late Future<_ProxyPageData> _pageFuture;

  @override
  void initState() {
    super.initState();
    _pageFuture = _loadPage();
  }

  Future<_ProxyPageData> _loadPage() async {
    final residentPage = await widget.controller.listProxyResidents();
    var helpers = VolunteerHelperList(items: const [], isPartial: false);
    var helperLoadFailed = false;
    try {
      helpers = await widget.controller.listVolunteerHelpers();
    } catch (_) {
      helperLoadFailed = true;
    }
    final campaignController = widget.taskCampaignController;
    final taskBoundary = campaignController?.boundary;
    final tasks =
        campaignController != null &&
            taskBoundary is TaskCampaignManagementBoundary
        ? await campaignController.listActiveTaskCampaigns()
        : const <ActiveTaskCampaignRecord>[];
    return _ProxyPageData(
      residents: residentPage.residents,
      isPartial: residentPage.isPartial,
      helpers: helpers,
      helperLoadFailed: helperLoadFailed,
      tasks: tasks,
    );
  }

  void _reload() {
    setState(() {
      _pageFuture = _loadPage();
    });
  }

  Future<void> _createProxyResident() async {
    PendingProxyResidentCreate? pending;
    try {
      pending = await widget.controller.getPendingCreate(
        communityId: widget.profile.communityId,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ProxyCreateRequestScopeMismatch
                  ? 'Permintaan tersimpan terkait RT lain. Kembali ke RT asal untuk menyelesaikannya.'
                  : 'Permintaan tersimpan belum dapat dibaca dengan aman.',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateProxyResidentDialog(
        pending: pending,
        onCancelPending: pending == null
            ? null
            : () => widget.controller.cancelPendingProxyResidentCreate(
                communityId: widget.profile.communityId,
              ),
        onSubmit:
            ({
              required nickname,
              required houseNumber,
              required needsAssistance,
            }) => widget.controller.createProxyResident(
              communityId: widget.profile.communityId,
              nickname: nickname,
              houseNumber: houseNumber,
              needsAssistance: needsAssistance,
              residentConsentConfirmed: true,
            ),
      ),
    );
    if (submitted == true && mounted) _reload();
  }

  Future<void> _updateAssistance(ProxyResidentRecord resident) async {
    final nextValue = !resident.needsAssistance;
    var consentConfirmed = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            nextValue ? 'Catat kebutuhan dukungan?' : 'Hapus penanda dukungan?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nextValue
                    ? 'Catat penanda dukungan untuk ${resident.nickname}. Jangan masukkan diagnosis.'
                    : 'Penanda dukungan untuk ${resident.nickname} akan dihapus.',
              ),
              CheckboxListTile(
                value: consentConfirmed,
                onChanged: (value) =>
                    setDialogState(() => consentConfirmed = value ?? false),
                title: const Text('Warga menyetujui perubahan ini.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Kembali'),
            ),
            FilledButton(
              key: const Key('proxy-assistance-confirm'),
              onPressed: consentConfirmed
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Simpan perubahan'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.updateProxyAssistance(
        residentId: resident.residentId,
        needsAssistance: nextValue,
        residentConsentConfirmed: true,
      );
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status bantuan belum dapat diperbarui.'),
          ),
        );
      }
    }
  }

  Future<void> _deleteResidentData(ProxyResidentRecord resident) async {
    var residentRequestConfirmed = false;
    var identityVerificationConfirmed = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            resident.deletionPending
                ? 'Lanjutkan penghapusan data warga'
                : 'Hapus data warga?',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  resident.deletionPending
                      ? 'Penghapusan data ${resident.nickname} belum selesai. '
                            'Lanjutkan proses yang sama; akses warga tetap dibatasi.'
                      : 'Data profil ${resident.nickname}, sesi warga, status tugas, '
                            'usulan, penanda bantuan, dan foto bukti akan dihapus '
                            'dari server. Riwayat kampanye RT tetap tersimpan.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Alat ini tidak memulihkan identitas. Lanjutkan hanya setelah '
                  'prosedur verifikasi identitas offline ditetapkan untuk pilot '
                  'dan telah dilakukan.',
                ),
                CheckboxListTile(
                  key: const Key('proxy-delete-request-consent'),
                  contentPadding: EdgeInsets.zero,
                  value: residentRequestConfirmed,
                  onChanged: (value) => setDialogState(
                    () => residentRequestConfirmed = value ?? false,
                  ),
                  title: const Text('Warga meminta penghapusan data.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  key: const Key('proxy-delete-identity-check'),
                  contentPadding: EdgeInsets.zero,
                  value: identityVerificationConfirmed,
                  onChanged: (value) => setDialogState(
                    () => identityVerificationConfirmed = value ?? false,
                  ),
                  title: const Text(
                    'Verifikasi identitas offline sudah dilakukan.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              key: const Key('proxy-delete-confirm'),
              onPressed:
                  residentRequestConfirmed && identityVerificationConfirmed
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Hapus data'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.deleteResidentData(
        residentId: resident.residentId,
        residentRequestConfirmed: true,
        identityVerificationConfirmed: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data warga telah dihapus dari server.'),
          ),
        );
        _reload();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Penghapusan belum selesai. Data warga dibatasi sementara; '
              'periksa koneksi lalu coba lagi.',
            ),
          ),
        );
        _reload();
      }
    }
  }

  Future<void> _assignHelper(
    ProxyResidentRecord resident,
    VolunteerHelperList helpers,
  ) async {
    if (helpers.items.isEmpty) return;
    VolunteerHelperRecord? selected = helpers.items.first;
    final selectedHelper = await showDialog<VolunteerHelperRecord>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tawarkan bantuan sukarela'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Pilih relawan untuk ${resident.nickname}. Relawan sudah '
                'menyatakan bersedia, tetapi tetap bebas menerima atau menolak '
                'permintaan ini.',
              ),
              const SizedBox(height: 12),
              if (helpers.isPartial)
                const Text(
                  'Daftar relawan dibatasi hingga 200 orang dan belum lengkap.',
                ),
              DropdownButtonFormField<String>(
                key: const Key('proxy-helper-picker'),
                initialValue: selected?.residentId,
                decoration: const InputDecoration(labelText: 'Relawan'),
                items: [
                  for (final helper in helpers.items)
                    DropdownMenuItem(
                      value: helper.residentId,
                      child: Text(
                        '${helper.nickname} · ${helper.residentId.substring(36)}',
                      ),
                    ),
                ],
                onChanged: (value) => setDialogState(() {
                  selected = helpers.items.firstWhere(
                    (helper) => helper.residentId == value,
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              key: const Key('proxy-helper-assign-confirm'),
              onPressed: selected == null
                  ? null
                  : () => Navigator.of(dialogContext).pop(selected),
              child: const Text('Kirim permintaan'),
            ),
          ],
        ),
      ),
    );
    if (selectedHelper == null || !mounted) return;
    try {
      await widget.controller.createHelperAssignment(
        residentId: resident.residentId,
        helperResidentId: selectedHelper.residentId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permintaan bantuan dikirim. Relawan dapat menerima atau menolak.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permintaan belum tersimpan atau pasangan sudah aktif.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateStatus({
    required ProxyResidentRecord resident,
    required String taskId,
    required String participationState,
    required bool completionReported,
  }) async {
    try {
      final result = await widget.controller.updateProxyTaskStatus(
        residentId: resident.residentId,
        taskId: taskId,
        participationState: participationState,
        completionReported: completionReported,
        residentConsentConfirmed: true,
      );
      if (!mounted) return;
      final message = result.completionState == 'PENDING_RT_VERIFICATION'
          ? 'Laporan menunggu verifikasi RT.'
          : participationState == 'DECLINED'
          ? 'Pilihan Tidak Ikut dicatat tanpa penalti.'
          : 'Pilihan Ikut dicatat.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Status belum tersimpan. Periksa koneksi dan coba lagi.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dukungan Warga RT')),
    body: FutureBuilder<_ProxyPageData>(
      future: _pageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Data warga belum dapat dimuat untuk RT ini.'),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('proxy-resident-retry'),
                  onPressed: _reload,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          );
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${widget.profile.role.label} · RT ${widget.profile.communityId}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Daftar ini hanya untuk operator RT yang berwenang. '
                    'Gunakan nama panggilan dan nomor rumah opsional. Jangan '
                    'catat diagnosis, alamat lengkap, atau koordinat. Status '
                    'Ikut/Tidak Ikut harus dikonfirmasi kepada warga dan tetap '
                    'sukarela.',
                  ),
                ),
              ),
              if (data.helperLoadFailed) ...[
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Daftar relawan belum dapat dimuat. Status warga tetap '
                      'tersedia; coba muat ulang sebelum memasangkan relawan.',
                    ),
                  ),
                ),
              ],
              if (data.isPartial) ...[
                const SizedBox(height: 12),
                const Card(
                  key: Key('proxy-resident-partial-warning'),
                  color: Color(0xFFFFF1D6),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Menampilkan 200 warga pertama. Daftar belum lengkap; '
                      'warga lain mungkin tidak terlihat atau dapat dipilih. '
                      'Jangan anggap ini daftar penuh.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('proxy-resident-create'),
                onPressed: _createProxyResident,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Catat warga tanpa aplikasi'),
              ),
              const SizedBox(height: 16),
              if (data.residents.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Belum ada profil warga di RT ini.',
                    key: Key('proxy-resident-empty'),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final resident in data.residents) ...[
                  _ProxyResidentCard(
                    key: ValueKey(resident.residentId),
                    resident: resident,
                    helpers: data.helpers,
                    tasks: data.tasks,
                    canUpdateTasks:
                        !resident.deletionPending &&
                        widget.taskCampaignController != null &&
                        widget.taskCampaignController!.boundary
                            is TaskCampaignManagementBoundary,
                    onUpdateAssistance: () => _updateAssistance(resident),
                    onAssignHelper: () => _assignHelper(resident, data.helpers),
                    onDelete: () => _deleteResidentData(resident),
                    onLoadTaskStatus: (taskId) =>
                        widget.controller.getProxyTaskStatus(
                          residentId: resident.residentId,
                          taskId: taskId,
                        ),
                    onUpdateStatus: (taskId, state, completed) => _updateStatus(
                      resident: resident,
                      taskId: taskId,
                      participationState: state,
                      completionReported: completed,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    ),
  );
}

final class _CreateProxyResidentDialog extends StatefulWidget {
  const _CreateProxyResidentDialog({
    required this.onSubmit,
    this.onCancelPending,
    this.pending,
  });

  final PendingProxyResidentCreate? pending;
  final Future<String> Function()? onCancelPending;
  final Future<void> Function({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
  })
  onSubmit;

  @override
  State<_CreateProxyResidentDialog> createState() =>
      _CreateProxyResidentDialogState();
}

final class _CreateProxyResidentDialogState
    extends State<_CreateProxyResidentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _houseNumber;
  late bool _needsAssistance;
  late bool _consentConfirmed;
  bool _busy = false;

  bool get _isRetry => widget.pending != null;

  @override
  void initState() {
    super.initState();
    final pending = widget.pending;
    _nickname = TextEditingController(text: pending?.nickname ?? '');
    _houseNumber = TextEditingController(text: pending?.houseNumber ?? '');
    _needsAssistance = pending?.needsAssistance ?? false;
    _consentConfirmed = pending?.residentConsentConfirmed ?? false;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _houseNumber.dispose();
    super.dispose();
  }

  Future<void> _cancelPending() async {
    final cancel = widget.onCancelPending;
    if (cancel == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan permintaan tersimpan?'),
        content: const Text(
          'Server akan memastikan profil belum dibuat sebelum membatalkan. '
          'Jika profil sudah dibuat, permintaan tetap tersimpan dan data warga '
          'tidak akan dihapus otomatis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: const Key('proxy-create-cancel-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Periksa dan batalkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final state = await cancel();
      if (!mounted) return;
      if (state == 'CANCELLED' || state == 'CREATED' || state == 'DELETED') {
        final message = switch (state) {
          'CANCELLED' => 'Permintaan dibatalkan sebelum profil dibuat.',
          'CREATED' => 'Profil sudah dibuat dan tampil di daftar RT. Data server tidak dihapus.',
          _ => 'Profil sudah dihapus dari server.',
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status permintaan belum dapat diperiksa.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status permintaan belum dapat diperiksa. Coba lagi.'),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || !_consentConfirmed) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(
        nickname: _nickname.text,
        houseNumber: _houseNumber.text.trim().isEmpty
            ? null
            : _houseNumber.text.trim(),
        needsAssistance: _needsAssistance,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data belum tersimpan. Periksa koneksi dan coba lagi.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _isRetry ? 'Kirim ulang pencatatan warga' : 'Catat warga tanpa aplikasi',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isRetry)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Permintaan sebelumnya belum mendapat konfirmasi server. '
                  'Kirim ulang data yang sama agar tidak membuat duplikat.',
                  key: Key('proxy-create-retry-notice'),
                ),
              ),
            TextFormField(
              key: const Key('proxy-nickname'),
              controller: _nickname,
              readOnly: _isRetry,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Nama panggilan',
                helperText: 'Gunakan nama panggilan, bukan nama lengkap.',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Wajib diisi.' : null,
            ),
            TextFormField(
              key: const Key('proxy-house-number'),
              controller: _houseNumber,
              readOnly: _isRetry,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: 'Nomor rumah (opsional)',
                helperText: 'Jangan masukkan alamat lengkap.',
              ),
            ),
            SwitchListTile(
              key: const Key('proxy-needs-assistance'),
              contentPadding: EdgeInsets.zero,
              value: _needsAssistance,
              onChanged: _busy || _isRetry
                  ? null
                  : (value) => setState(() => _needsAssistance = value),
              title: const Text('Perlu dukungan'),
              subtitle: const Text(
                'Jangan catat diagnosis atau alasan pribadi.',
              ),
            ),
            CheckboxListTile(
              key: const Key('proxy-consent-attestation'),
              contentPadding: EdgeInsets.zero,
              value: _consentConfirmed,
              onChanged: _busy || _isRetry
                  ? null
                  : (value) =>
                        setState(() => _consentConfirmed = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                _isRetry
                    ? 'Persetujuan awal tersimpan untuk permintaan ini.'
                    : 'Warga menyetujui pencatatan ini.',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (_isRetry)
        TextButton(
          key: const Key('proxy-create-cancel-pending'),
          onPressed: _busy ? null : _cancelPending,
          child: const Text('Batalkan permintaan tersimpan'),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Batal'),
      ),
      FilledButton(
        key: const Key('proxy-create-confirm'),
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Menyimpan…' : 'Simpan'),
      ),
    ],
  );
}

final class _ProxyResidentCard extends StatefulWidget {
  const _ProxyResidentCard({
    required this.resident,
    required this.helpers,
    required this.tasks,
    required this.canUpdateTasks,
    required this.onUpdateAssistance,
    required this.onAssignHelper,
    required this.onDelete,
    required this.onLoadTaskStatus,
    required this.onUpdateStatus,
    super.key,
  });

  final ProxyResidentRecord resident;
  final VolunteerHelperList helpers;
  final List<ActiveTaskCampaignRecord> tasks;
  final bool canUpdateTasks;
  final VoidCallback onUpdateAssistance;
  final VoidCallback onAssignHelper;
  final VoidCallback onDelete;
  final Future<ProxyTaskStatusRecord> Function(String taskId) onLoadTaskStatus;
  final void Function(String taskId, String participation, bool completed)
  onUpdateStatus;

  @override
  State<_ProxyResidentCard> createState() => _ProxyResidentCardState();
}

final class _ProxyResidentCardState extends State<_ProxyResidentCard> {
  String? _taskId;
  String? _participation;
  bool _completionReported = false;
  bool _consentConfirmed = false;
  bool _statusExpanded = false;
  Future<ProxyTaskStatusRecord>? _statusFuture;

  @override
  void initState() {
    super.initState();
    _taskId = widget.tasks.isEmpty ? null : widget.tasks.first.taskId;
  }

  @override
  void didUpdateWidget(covariant _ProxyResidentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.tasks.any((task) => task.taskId == _taskId)) {
      _taskId = widget.tasks.isEmpty ? null : widget.tasks.first.taskId;
      _participation = null;
      _completionReported = false;
      _consentConfirmed = false;
      _statusFuture = _statusExpanded ? _loadStatus(_taskId) : null;
    }
  }

  Future<ProxyTaskStatusRecord>? _loadStatus(String? taskId) {
    if (!widget.canUpdateTasks || taskId == null) return null;
    return widget.onLoadTaskStatus(taskId);
  }

  void _selectTask(String? taskId) {
    setState(() {
      _taskId = taskId;
      _participation = null;
      _completionReported = false;
      _consentConfirmed = false;
      _statusFuture = _statusExpanded ? _loadStatus(taskId) : null;
    });
  }

  void _onStatusSectionExpanded(bool expanded) {
    setState(() {
      _statusExpanded = expanded;
      if (expanded && _statusFuture == null) {
        _statusFuture = _loadStatus(_taskId);
      }
    });
  }

  void _selectParticipation(String? value) {
    setState(() {
      _participation = value;
      _completionReported = false;
      _consentConfirmed = false;
    });
  }

  void _setCompletionReported(bool? value) {
    setState(() {
      _completionReported = value ?? false;
      _consentConfirmed = false;
    });
  }

  ActiveTaskCampaignRecord? get _selectedTask {
    for (final task in widget.tasks) {
      if (task.taskId == _taskId) return task;
    }
    return null;
  }

  Widget _buildStatusEditor(
    BuildContext context,
    ProxyTaskStatusRecord status,
  ) {
    final storedParticipation = status.participationState == 'UNRESPONDED'
        ? null
        : status.participationState;
    final participation = storedParticipation ?? _participation;
    final isRecorded = storedParticipation != null;
    final canReportCompletion =
        participation == 'JOINED' && status.completionState == 'NOT_SUBMITTED';
    final canSave =
        _consentConfirmed &&
        (isRecorded
            ? status.participationState == 'JOINED' &&
                  status.completionState == 'NOT_SUBMITTED' &&
                  _completionReported
            : participation != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('proxy-participation-picker'),
          initialValue: participation,
          decoration: const InputDecoration(
            labelText: 'Pilihan warga',
            hintText: 'Pilih Ikut atau Tidak Ikut',
          ),
          items: const [
            DropdownMenuItem(value: 'JOINED', child: Text('Ikut')),
            DropdownMenuItem(value: 'DECLINED', child: Text('Tidak Ikut')),
          ],
          onChanged: isRecorded ? null : _selectParticipation,
        ),
        if (isRecorded)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              participation == 'DECLINED'
                  ? 'Pilihan tercatat: Tidak Ikut. Pilihan ini sah dan tanpa penalti.'
                  : 'Pilihan tercatat: Ikut.',
              key: const Key('proxy-recorded-participation'),
            ),
          ),
        if (participation == 'JOINED' && canReportCompletion)
          CheckboxListTile(
            key: const Key('proxy-completion-reported'),
            contentPadding: EdgeInsets.zero,
            value: _completionReported,
            onChanged: _setCompletionReported,
            title: const Text('Warga melaporkan tugas selesai'),
            subtitle: const Text('Laporan tetap menunggu verifikasi RT.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        if (status.completionState == 'PENDING_RT_VERIFICATION')
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Menunggu Verifikasi RT',
              key: Key('proxy-completion-pending'),
            ),
          ),
        if (status.completionState == 'VERIFIED_COMPLETE')
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Penyelesaian telah diverifikasi RT.',
              key: Key('proxy-completion-verified'),
            ),
          ),
        if (!isRecorded || canReportCompletion) ...[
          CheckboxListTile(
            key: const Key('proxy-status-consent'),
            contentPadding: EdgeInsets.zero,
            value: _consentConfirmed,
            onChanged: participation == null
                ? null
                : (value) => setState(() => _consentConfirmed = value ?? false),
            title: Text(
              isRecorded
                  ? 'Warga menyetujui laporan penyelesaian ini.'
                  : 'Warga mengonfirmasi pilihan ini.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          FilledButton(
            key: const Key('proxy-status-save'),
            onPressed: _taskId == null || !canSave
                ? null
                : () => widget.onUpdateStatus(
                    _taskId!,
                    participation!,
                    _completionReported,
                  ),
            child: Text(
              isRecorded
                  ? 'Kirim laporan untuk verifikasi RT'
                  : 'Simpan status sukarela',
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          participation == 'DECLINED'
              ? 'Tidak Ikut adalah pilihan yang sah dan tanpa penalti.'
              : 'Status tidak mengubah tugas dan tidak mengesahkan penyelesaian.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedTask = _selectedTask;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.resident.nickname,
                    key: const Key('proxy-resident-nickname'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (!widget.resident.deletionPending &&
                    widget.resident.needsAssistance)
                  const Chip(
                    key: Key('proxy-assistance-marker'),
                    label: Text('Perlu dukungan'),
                    avatar: Icon(Icons.support_outlined),
                  ),
              ],
            ),
            if (widget.resident.deletionPending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Penghapusan sedang diproses. Perubahan lain dinonaktifkan.',
                  key: Key('proxy-deletion-pending'),
                ),
              ),
            if (!widget.resident.deletionPending &&
                widget.resident.houseNumber != null)
              Text('Nomor rumah ${widget.resident.houseNumber}'),
            TextButton.icon(
              key: const Key('proxy-assistance-toggle'),
              onPressed: widget.resident.deletionPending
                  ? null
                  : widget.onUpdateAssistance,
              icon: const Icon(Icons.edit_outlined),
              label: Text(
                widget.resident.needsAssistance
                    ? 'Perbarui penanda dukungan'
                    : 'Catat kebutuhan dukungan',
              ),
            ),
            if (!widget.resident.deletionPending &&
                widget.resident.needsAssistance)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('proxy-helper-assign'),
                  onPressed: widget.helpers.items.isEmpty
                      ? null
                      : widget.onAssignHelper,
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Tawarkan bantuan relawan'),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('proxy-resident-delete'),
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  widget.resident.deletionPending
                      ? 'Lanjutkan penghapusan'
                      : 'Hapus data warga',
                ),
              ),
            ),
            const Divider(),
            ExpansionTile(
              key: const Key('proxy-task-status-section'),
              title: Text('Status tugas', style: theme.textTheme.titleMedium),
              onExpansionChanged: _onStatusSectionExpanded,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: !widget.canUpdateTasks || widget.tasks.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Tidak ada tugas aktif yang dapat diperbarui.',
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              key: const Key('proxy-task-picker'),
                              initialValue: _taskId,
                              decoration: const InputDecoration(
                                labelText: 'Tugas aktif',
                              ),
                              items: [
                                for (final task in widget.tasks)
                                  DropdownMenuItem(
                                    value: task.taskId,
                                    child: Text(task.templateSnapshot.title),
                                  ),
                              ],
                              onChanged: _selectTask,
                            ),
                            if (selectedTask != null)
                              Card(
                                key: const Key(
                                  'proxy-task-safety-instructions',
                                ),
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Petunjuk tugas: ${selectedTask.templateSnapshot.title}',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        selectedTask
                                            .templateSnapshot
                                            .coreInstruction,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Keselamatan: ${selectedTask.templateSnapshot.safetyInstruction}',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme.colorScheme.error,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (_statusFuture == null)
                              const Text('Status tugas belum dapat diperiksa.')
                            else
                              FutureBuilder<ProxyTaskStatusRecord>(
                                future: _statusFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  if (snapshot.hasError ||
                                      snapshot.data == null) {
                                    return const Text(
                                      'Status tugas belum dapat dimuat. Coba lagi nanti.',
                                      key: Key('proxy-status-load-error'),
                                    );
                                  }
                                  return _buildStatusEditor(
                                    context,
                                    snapshot.data!,
                                  );
                                },
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
