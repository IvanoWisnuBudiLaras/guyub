import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/application/resident_session.dart';
import '../application/emergency_directory.dart';
import '../application/emergency_directory_controller.dart';
import '../application/emergency_directory_cache.dart';

/// Offline-readable emergency directory. Pass no session to show the latest
/// public directory saved on this device from the unauthenticated Darurat route.
final class EmergencyDirectoryScreen extends StatefulWidget {
  const EmergencyDirectoryScreen({
    required this.controller,
    this.session,
    this.onLaunchUri,
    super.key,
  });

  final EmergencyDirectoryController controller;
  final ResidentSession? session;
  final Future<bool> Function(Uri uri)? onLaunchUri;

  @override
  State<EmergencyDirectoryScreen> createState() =>
      _EmergencyDirectoryScreenState();
}

final class _EmergencyDirectoryScreenState
    extends State<EmergencyDirectoryScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant EmergencyDirectoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _load();
    } else if (oldWidget.session != widget.session) {
      _load();
    }
  }

  Future<void> _openOfficialUri(Uri uri) async {
    var didLaunch = false;
    try {
      didLaunch = widget.onLaunchUri == null
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : await widget.onLaunchUri!(uri);
    } catch (_) {
      didLaunch = false;
    }
    if (!mounted || didLaunch) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Kanal resmi tidak dapat dibuka. Periksa koneksi atau gunakan kanal lain yang tercantum.',
        ),
      ),
    );
  }

  void _load() {
    final session = widget.session;
    if (session == null) {
      widget.controller.loadLatest();
    } else {
      widget.controller.load(session: session);
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final snapshot = state.snapshot;
    final directory = snapshot?.directory;
    final areaName = snapshot?.communityName ?? widget.session?.communityName;
    final rtLabel = snapshot?.rtLabel ?? widget.session?.rtLabel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informasi Darurat'),
        actions: [
          IconButton(
            key: const Key('emergency-directory-refresh'),
            tooltip: widget.session == null
                ? 'Muat ulang data tersimpan'
                : 'Perbarui direktori',
            onPressed: state.isRefreshing ? null : widget.controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: widget.controller.refresh,
        child: ListView(
          key: const Key('emergency-directory-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _StatusCard(state: state),
            const SizedBox(height: 12),
            if (areaName != null && rtLabel != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Data untuk wilayah',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$areaName • $rtLabel',
                        key: const Key('emergency-directory-area'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pastikan wilayah ini sesuai dengan lokasi Anda. '
                        'Direktori ini tidak berlaku otomatis untuk RT lain.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (snapshot != null) ...[
              _SyncDetails(snapshot: snapshot),
              const SizedBox(height: 12),
              _ContactSection(items: directory!.emergencyContacts),
              const SizedBox(height: 12),
              _AssemblySection(items: directory.assemblyPoints),
              const SizedBox(height: 12),
              _OfficialChannelSection(
                items: directory.officialReportChannels,
                onLaunchUri: _openOfficialUri,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Guyub.id tidak menggantikan layanan darurat atau pelaporan resmi.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              _EmptyMessage(state: state),
            ],
          ],
        ),
      ),
    );
  }
}

final class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final EmergencyDirectoryViewState state;

  @override
  Widget build(BuildContext context) {
    final String message;
    final IconData icon;
    final Color? backgroundColor;
    if (state.hasConflict && state.snapshot != null) {
      message = 'Versi direktori berbeda. Data tersimpan sebelumnya tetap ditampilkan.';
      icon = Icons.warning_amber_outlined;
      backgroundColor = Theme.of(context).colorScheme.errorContainer
          .withValues(alpha: 0.5);
    } else if (state.hasConflict) {
      message = 'Data direktori tidak konsisten dan tidak dapat ditampilkan. Coba perbarui lagi.';
      icon = Icons.warning_amber_outlined;
      backgroundColor = Theme.of(context).colorScheme.errorContainer
          .withValues(alpha: 0.5);
    } else if (state.isOffline) {
      message =
          'Mode offline • menampilkan direktori yang tersimpan di perangkat.';
      icon = Icons.cloud_off_outlined;
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    } else if (state.isRefreshing) {
      message = 'Memeriksa pembaruan direktori…';
      icon = Icons.sync;
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerLow;
    } else if (state.status == EmergencyDirectoryViewStatus.active) {
      message = 'Direktori tersinkron.';
      icon = Icons.cloud_done_outlined;
      backgroundColor = Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.3);
    } else if (state.status == EmergencyDirectoryViewStatus.disabled) {
      message = 'Direktori darurat untuk wilayah ini sedang dinonaktifkan.';
      icon = Icons.info_outline;
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    } else if (state.status == EmergencyDirectoryViewStatus.unconfigured) {
      message = 'Direktori darurat belum dikonfigurasi untuk wilayah ini.';
      icon = Icons.info_outline;
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    } else if (state.status == EmergencyDirectoryViewStatus.loading) {
      message = 'Memuat informasi darurat…';
      icon = Icons.sync;
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerLow;
    } else {
      message = 'Direktori belum tersedia. Periksa koneksi lalu coba lagi.';
      icon = Icons.cloud_off_outlined;
      backgroundColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              key: const Key('emergency-directory-status'),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          if (state.isRefreshing) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}

final class _SyncDetails extends StatelessWidget {
  const _SyncDetails({required this.snapshot});

  final EmergencyDirectoryCacheSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Terakhir disinkronkan: ${_formatDate(snapshot.syncedAt)}'),
            const SizedBox(height: 6),
            Text(
              'Terakhir diverifikasi: '
              '${_formatDate(snapshot.directory.lastVerifiedAt!)}',
            ),
          ],
        ),
      ),
    );
  }
}

final class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.items});

  final List<EmergencyContact> items;

  @override
  Widget build(BuildContext context) => _DirectorySection(
    title: 'Kontak Darurat',
    icon: Icons.phone_in_talk_outlined,
    children: [
      if (items.isEmpty)
        Text(
          'Belum ada kontak darurat yang dicantumkan.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        )
      else
        ...items.map(
          (item) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.phone_outlined,
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
                        item.label,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        item.phone,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final uri = Uri.parse('tel:${item.phone}');
                    try {
                      await launchUrl(uri);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Tidak dapat membuka aplikasi telepon.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Telepon'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

final class _AssemblySection extends StatelessWidget {
  const _AssemblySection({required this.items});

  final List<EmergencyAssemblyPoint> items;

  @override
  Widget build(BuildContext context) => _DirectorySection(
    title: 'Titik Kumpul',
    icon: Icons.place_outlined,
    children: [
      if (items.isEmpty)
        Text(
          'Belum ada titik kumpul yang dicantumkan.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        )
      else
        ...items.map(
          (item) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.location_on_outlined,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.publicLocation,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

final class _OfficialChannelSection extends StatelessWidget {
  const _OfficialChannelSection({
    required this.items,
    required this.onLaunchUri,
  });

  final List<OfficialReportChannel> items;
  final Future<void> Function(Uri uri) onLaunchUri;

  @override
  Widget build(BuildContext context) => _DirectorySection(
    title: 'Kanal Pelaporan Resmi',
    icon: Icons.account_balance_outlined,
    children: [
      if (items.isEmpty)
        Text(
          'Belum ada kanal pelaporan resmi yang dikonfigurasi untuk wilayah ini.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        )
      else ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Masalah di luar kapasitas warga? Gunakan salah satu kanal resmi yang dikonfigurasi untuk RT ini.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(items.length, (index) {
          final item = items[index];
          final urlUri = item.safeUrlUri;
          final phoneUri = item.safePhoneUri;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.account_balance_outlined,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (item.url != null) ...[
                            const SizedBox(height: 4),
                            SelectableText(
                              item.url!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                          if (item.phone != null) ...[
                            const SizedBox(height: 4),
                            SelectableText(
                              item.phone!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (urlUri != null || phoneUri != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (urlUri != null)
                        OutlinedButton.icon(
                          key: Key('official-report-url-$index'),
                          onPressed: () => onLaunchUri(urlUri),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Buka situs'),
                        ),
                      if (phoneUri != null)
                        FilledButton.tonalIcon(
                          key: Key('official-report-phone-$index'),
                          onPressed: () => onLaunchUri(phoneUri),
                          icon: const Icon(Icons.phone_outlined, size: 18),
                          label: const Text('Telepon'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    ],
  );
}

final class _DirectorySection extends StatelessWidget {
  const _DirectorySection({
    required this.title,
    required this.children,
    this.icon,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

final class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.state});

  final EmergencyDirectoryViewState state;

  @override
  Widget build(BuildContext context) {
    final message = switch (state.status) {
      EmergencyDirectoryViewStatus.disabled =>
        'Informasi darurat untuk wilayah ini sedang dinonaktifkan.',
      EmergencyDirectoryViewStatus.unconfigured =>
        'Informasi darurat belum dikonfigurasi untuk RT ini.',
      EmergencyDirectoryViewStatus.loading =>
        'Informasi darurat sedang dimuat.',
      EmergencyDirectoryViewStatus.unavailable =>
        state.isOffline
            ? 'Belum ada direktori darurat tersimpan di perangkat ini.'
            : 'Informasi darurat belum dapat dimuat. Coba lagi saat tersambung.',
      EmergencyDirectoryViewStatus.active =>
        'Belum ada informasi darurat yang tersedia.',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Safe fallback for test or degraded runtimes with no local persistence.
final class EmergencyDirectoryUnavailableScreen extends StatelessWidget {
  const EmergencyDirectoryUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Informasi Darurat')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 40),
            SizedBox(height: 12),
            Text(
              'Direktori belum tersedia pada perangkat ini. Gunakan kanal darurat resmi setempat.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              'Guyub.id tidak menggantikan layanan darurat atau pelaporan resmi.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
