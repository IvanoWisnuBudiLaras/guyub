import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/tinted_info_box.dart';

/// Modal lembar penjelasan privasi sebelum warga mengambil foto dan menyalakan GPS.
final class TreePrivacyRationaleSheet extends StatelessWidget {
  const TreePrivacyRationaleSheet({super.key});

  /// Menampilkan lembar penjelasan privasi sebagai BottomSheet.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TreePrivacyRationaleSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.park_outlined,
                  color: colors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privasi Titik Pohon Guyub',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Perlindungan data lokasi & foto warga',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Rationale points
          TintedInfoBox(
            tint: TintType.info,
            icon: Icons.shield_outlined,
            title: 'Bagaimana Lokasi Anda Dilindungi:',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SizedBox(height: 4),
                Text(
                  '• Grid Kasar (~150m): Tetangga di RT hanya melihat perkiraan sel area, bukan titik presisi rumah Anda.',
                ),
                SizedBox(height: 4),
                Text(
                  '• Verifikasi Lapangan: Koordinat presisi hanya dapat diakses oleh Ketua RT untuk memverifikasi bibit.',
                ),
                SizedBox(height: 4),
                Text(
                  '• Sanitasi Foto: Metadata EXIF/GPS dihapus sebelum upload, dan foto dibersihkan dari server setelah 30 hari.',
                ),
                SizedBox(height: 4),
                Text(
                  '• Partisipasi Sukarela: Tanpa kuota, denda, atau peringkat individu.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tombol Aksi
          FilledButton.icon(
            key: const Key('tree-privacy-agree-button'),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Saya Mengerti & Lanjutkan'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('tree-privacy-cancel-button'),
            onPressed: () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }
}
