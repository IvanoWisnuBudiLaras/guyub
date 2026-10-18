import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_logo.dart';

/// Wordmark "GUYUB.ID" berwarna biru, sesuai mockup proposal.
///
/// Dengan [showLogo] true, logo Guyub tampil di sebelah kiri (dipakai pada
/// layar pemilihan peran).
final class GuyubWordmark extends StatelessWidget {
  const GuyubWordmark({this.showLogo = false, this.fontSize = 15, super.key});

  final bool showLogo;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLogo) ...[
          AppLogo(size: fontSize * 2.2),
          const SizedBox(width: 4),
        ],
        Text(
          'GUYUB.ID',
          style: TextStyle(
            color: colors.primary,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

/// Satu baris aksi pada sheet pengaturan (ikon roda gigi).
final class GuyubMenuAction {
  const GuyubMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.key,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final Key? key;
  final bool destructive;
}

/// AppBar beranda sesuai proposal: wordmark GUYUB.ID di kiri, ikon lonceng
/// dan roda gigi di kanan.
///
/// [semanticTitle] tetap diekspos ke aksesibilitas agar judul layar lama
/// (mis. "Ruang Operator") tetap dapat ditemukan oleh pembaca layar/E2E.
final class GuyubTopBar extends StatelessWidget implements PreferredSizeWidget {
  const GuyubTopBar({
    required this.semanticTitle,
    required this.menuActions,
    this.extraActions = const [],
    this.notificationContent,
    super.key,
  });

  final String semanticTitle;
  final List<GuyubMenuAction> menuActions;
  final List<Widget> extraActions;

  /// Isi sheet notifikasi. Bila null, tampil pesan "belum ada notifikasi".
  final Widget? notificationContent;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _showNotifications(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifikasi',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              notificationContent ??
                  Text(
                    'Belum ada notifikasi baru di perangkat ini. Tugas baru '
                    'dari RT akan muncul di tab Tugas.',
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in menuActions)
              ListTile(
                key: action.key,
                leading: Icon(
                  action.icon,
                  color: action.destructive
                      ? sheetContext.appColors.danger
                      : null,
                ),
                title: Text(
                  action.label,
                  style: TextStyle(
                    color: action.destructive
                        ? sheetContext.appColors.danger
                        : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  action.onSelected();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: Semantics(
        header: true,
        label: semanticTitle,
        container: true,
        child: const ExcludeSemantics(child: GuyubWordmark()),
      ),
      actions: [
        ...extraActions,
        IconButton(
          key: const Key('top-bar-notifications'),
          tooltip: 'Notifikasi',
          onPressed: () => _showNotifications(context),
          icon: const Icon(Icons.notifications_none, size: 24),
        ),
        IconButton(
          key: const Key('top-bar-settings'),
          tooltip: 'Pengaturan',
          onPressed: () => _showSettings(context),
          icon: const Icon(Icons.settings_outlined, size: 24),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
