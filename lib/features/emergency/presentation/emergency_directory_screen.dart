import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/application/resident_session.dart';
import '../../../core/theme/guyub_tokens.dart';
import '../../../core/utils/indonesian_date_formatter.dart';
import '../../../core/widgets/inline_action_button.dart';
import '../../../core/widgets/mockup_widgets.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/tinted_info_box.dart';
import '../application/emergency_directory.dart';
import '../application/emergency_directory_controller.dart';
import '../application/emergency_directory_cache.dart';
import '../application/national_emergency_numbers.dart';

/// Offline-readable emergency directory. Pass no session to show the latest
/// public directory saved on this device from the unauthenticated Darurat route.
final class EmergencyDirectoryScreen extends StatefulWidget {
  const EmergencyDirectoryScreen({
    required this.controller,
    this.session,
    this.onLaunchUri,
    this.showAppBar = true,
    super.key,
  });

  final EmergencyDirectoryController controller;
  final ResidentSession? session;
  final Future<bool> Function(Uri uri)? onLaunchUri;
  final bool showAppBar;

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

  Future<void> _openMapLocation(String label, String address) async {
    final query = Uri.encodeComponent('$label, $address');
    final geoUri = Uri.parse('geo:0,0?q=$query');
    final webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    var didLaunch = false;
    try {
      if (await canLaunchUrl(geoUri)) {
        didLaunch = await launchUrl(geoUri);
      } else if (await canLaunchUrl(webUri)) {
        didLaunch = await launchUrl(
          webUri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      didLaunch = false;
    }
    if (!mounted || didLaunch) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Aplikasi peta tidak tersedia atau alamat tidak dapat dibuka.',
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
    final rawSnapshot = state.snapshot;
    final isDemoSnapshot =
        rawSnapshot != null &&
        (rawSnapshot.communityName.toLowerCase().contains('demo') ||
            rawSnapshot.rtLabel.toLowerCase().contains('demo'));
    // Jangan tampilkan data RT demo ke pengguna tanpa sesi.
    final snapshot = (widget.session == null && isDemoSnapshot)
        ? null
        : rawSnapshot;
    final directory = snapshot?.directory;
    final areaName = snapshot?.communityName ?? widget.session?.communityName;
    final rtLabel = snapshot?.rtLabel ?? widget.session?.rtLabel;

    final content = RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        key: const Key('emergency-directory-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _StatusCard(state: state),
          const SizedBox(height: 12),
          if (areaName != null && rtLabel != null) ...[
            SectionCard(
              title: 'Data untuk wilayah',
              icon: Icons.location_on_outlined,
              margin: EdgeInsets.zero,
              children: [
                Text(
                  '$areaName • $rtLabel',
                  key: const Key('emergency-directory-area'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pastikan wilayah ini sesuai dengan lokasi Anda. '
                  'Direktori ini tidak berlaku otomatis untuk RT lain.',
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (snapshot != null) ...[
            _SyncDetails(snapshot: snapshot),
            const SizedBox(height: 12),
            _ContactSection(items: directory!.emergencyContacts),
            const SizedBox(height: 12),
            _AssemblySection(
              items: directory.assemblyPoints,
              onOpenMap: _openMapLocation,
            ),
            const SizedBox(height: 12),
            _OfficialChannelSection(
              items: directory.officialReportChannels,
              onLaunchUri: _openOfficialUri,
            ),
            const SizedBox(height: 16),
            const TintedInfoBox(
              tint: TintType.info,
              icon: Icons.info_outline,
              child: Text(
                'Guyub.id tidak menggantikan layanan darurat atau pelaporan resmi.',
              ),
            ),
          ] else if (widget.session == null) ...[
            _UnauthenticatedEmergencyView(onLaunchUri: _openOfficialUri),
          ] else ...[
            _EmptyMessage(state: state),
          ],
        ],
      ),
    );

    if (!widget.showAppBar) {
      return content;
    }

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
      body: content,
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
      return TintedInfoBox.warning(
        text: 'Pembaruan terbaru belum bisa diterapkan. Menampilkan data tersimpan sebelumnya.',
        icon: Icons.warning_amber_rounded,
      );
    } else if (state.hasConflict) {
      return TintedInfoBox.warning(
        text: 'Data direktori tidak konsisten dan tidak dapat ditampilkan. Coba perbarui lagi.',
        icon: Icons.warning_amber_rounded,
      );
    } else if (state.isOffline) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: GuyubTokens.darkCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: GuyubTokens.yellowFill,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: GuyubTokens.yellowBorder),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.offline_bolt_outlined,
                    size: 12,
                    color: GuyubTokens.yellowText,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Offline',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: GuyubTokens.yellowText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mode offline • menampilkan direktori yang tersimpan di perangkat.',
                key: const Key('emergency-directory-status'),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      );
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
    return SectionCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      children: [
        Text('Terakhir disinkronkan: ${_formatDate(snapshot.syncedAt)}'),
        const SizedBox(height: 4),
        Text(
          'Terakhir diverifikasi: '
          '${_formatDate(snapshot.directory.lastVerifiedAt!)}',
        ),
      ],
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GuyubTokens.greyBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GuyubTokens.greenSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.phone_outlined,
                    color: GuyubTokens.green,
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
                        item.phone,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InlineActionButton(
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
                  icon: Icons.call,
                  label: 'Telepon',
                  variant: InlineActionButtonVariant.tonal,
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

final class _AssemblySection extends StatelessWidget {
  const _AssemblySection({required this.items, required this.onOpenMap});

  final List<EmergencyAssemblyPoint> items;
  final Future<void> Function(String label, String address) onOpenMap;

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
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GuyubTokens.greyBorder),
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
                        color: GuyubTokens.wargaHeroFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.location_on_outlined,
                        color: GuyubTokens.ctaBlue,
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
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: const [
                              GuyubPill(
                                label: 'Terkonfirmasi',
                                background: GuyubTokens.greenSoft,
                                foreground: GuyubTokens.green,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: InlineActionButton(
                    onPressed: () => onOpenMap(item.label, item.publicLocation),
                    icon: Icons.map_outlined,
                    label: 'Buka di Peta',
                    variant: InlineActionButtonVariant.outlined,
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
                            Text(
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
                            Text(
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
                        InlineActionButton(
                          key: Key('official-report-url-$index'),
                          onPressed: () => onLaunchUri(urlUri),
                          icon: Icons.open_in_new,
                          label: 'Buka situs',
                          variant: InlineActionButtonVariant.outlined,
                        ),
                      if (phoneUri != null)
                        InlineActionButton(
                          key: Key('official-report-phone-$index'),
                          onPressed: () => onLaunchUri(phoneUri),
                          icon: Icons.phone_outlined,
                          label: 'Telepon',
                          variant: InlineActionButtonVariant.tonal,
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
  Widget build(BuildContext context) => SectionCard(
    title: title,
    icon: icon,
    margin: EdgeInsets.zero,
    children: children,
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
    return TintedInfoBox.info(text: message, icon: Icons.info_outline);
  }
}

final class _UnauthenticatedEmergencyView extends StatelessWidget {
  const _UnauthenticatedEmergencyView({required this.onLaunchUri});

  final Future<void> Function(Uri uri) onLaunchUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TintedInfoBox.info(
          title: 'Belum Terhubung ke RT',
          icon: Icons.vpn_key_outlined,
          text:
              'Anda membuka informasi darurat tanpa sesi warga. '
              'Belum ada direktori darurat tersimpan di perangkat ini. '
              'Untuk melihat kontak pengurus RT, titik kumpul evakuasi lingkungan, '
              'dan kanal koordinasi warga Anda, silakan masuk dengan Kode RT '
              'pada menu Masuk Warga.',
        ),
        const SizedBox(height: 16),

        // Nomor Darurat Nasional Resmi
        SectionCard(
          title: 'Nomor darurat nasional',
          icon: Icons.shield_outlined,
          children: [
            Text(
              'Layanan darurat terverifikasi pemerintah RI (bebas pulsa / 24 jam)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ...kNationalEmergencyContacts.map(
              (contact) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
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
                            color: colorScheme.errorContainer.withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            contact.number,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                contact.label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                contact.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sumber: ${contact.sourceAuthority}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.outline,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        InlineActionButton(
                          onPressed: () =>
                              onLaunchUri(Uri.parse(contact.sourceUrl)),
                          icon: Icons.open_in_new,
                          label: 'Info Resmi',
                          variant: InlineActionButtonVariant.outlined,
                        ),
                        InlineActionButton(
                          onPressed: () async {
                            final uri = Uri.parse('tel:${contact.number}');
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
                          icon: Icons.call,
                          label: 'Panggil ${contact.number}',
                          variant: InlineActionButtonVariant.filled,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Disclaimer
        TintedInfoBox.danger(
          icon: Icons.info_outline,
          text: 'Guyub.id adalah platform kesiapsiagaan mandiri warga tingkat RT dan tidak menggantikan layanan darurat atau pelaporan resmi pemerintah.',
        ),
      ],
    );
  }
}

String _formatDate(DateTime value) =>
    IndonesianDateFormatter.formatNumeric(value);

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
