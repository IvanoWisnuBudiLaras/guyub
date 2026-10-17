import 'package:flutter/material.dart';

import '../../../../core/widgets/guyub_top_bar.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/guyub_tokens.dart';
import '../../application/operator_auth_boundary.dart';
import '../../application/operator_profile.dart';
import '../../application/resident_session.dart';
import '../../application/resident_session_controller.dart';

/// Entry point that keeps operator and resident paths visually distinct.
final class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({
    this.residentSessionController,
    this.operatorAuthBoundary,
    super.key,
  });

  final ResidentSessionController? residentSessionController;
  final OperatorAuthBoundary? operatorAuthBoundary;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

final class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  ResidentSession? _savedResidentSession;
  OperatorProfile? _savedOperatorProfile;

  @override
  void initState() {
    super.initState();
    _checkSavedSessions();
  }

  Future<void> _checkSavedSessions() async {
    try {
      if (widget.residentSessionController != null) {
        final session = await widget.residentSessionController!
            .restoreSession();
        if (mounted && session != null) {
          setState(() => _savedResidentSession = session);
        }
      }
    } catch (_) {}

    try {
      if (widget.operatorAuthBoundary != null) {
        final result = await widget.operatorAuthBoundary!
            .restoreCurrentSession();
        final profile = result.dataOrNull;
        if (mounted && profile != null) {
          setState(() => _savedOperatorProfile = profile);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 700; // Layar kecil seperti 360x640

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isCompact ? 16 : 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: logo + wordmark GUYUB.ID (kiri atas, sesuai proposal)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: GuyubWordmark(showLogo: true),
                  ),
                  SizedBox(height: isCompact ? 20 : 28),
                  Text(
                    'Masuk sebagai\nsiapa Anda?',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: isCompact ? 24 : 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pilih peran Anda di RT/RW.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SizedBox(height: isCompact ? 20 : 28),

                  // Kartu Lanjutkan Sesi jika ada sesi tersimpan
                  if (_savedResidentSession case final session?) ...[
                    _ResumeSessionCard(
                      key: const Key('resume-resident-session'),
                      title:
                          'Lanjutkan sebagai ${session.nickname} (${session.rtLabel})',
                      subtitle: session.communityName.isNotEmpty
                          ? session.communityName
                          : 'Sesi warga tersimpan',
                      icon: Icons.person_outline,
                      onTap: () => Navigator.of(context).pushReplacementNamed(
                        '/resident/home',
                        arguments: session,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_savedOperatorProfile case final operator?) ...[
                    _ResumeSessionCard(
                      key: const Key('resume-operator-session'),
                      title:
                          'Lanjutkan sebagai ${operator.displayName} (${operator.rtLabel})',
                      subtitle: operator.humanizedCommunityName,
                      icon: Icons.admin_panel_settings_outlined,
                      onTap: () => Navigator.of(context).pushReplacementNamed(
                        '/operator/home',
                        arguments: operator,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Operator card (kartu biru solid)
                  _RoleCard(
                    key: const Key('role-selection-operator'),
                    title: 'Saya Ketua RT/RW',
                    semanticTitle: 'Saya Ketua RT/RW atau Pendamping',
                    description:
                        'Kelola Tugas, pantau kesiapan warga, koordinasi banjir',
                    icon: Icons.assignment_outlined,
                    actionLabel: 'MASUK DENGAN AKUN',
                    isPrimary: true,
                    isCompact: isCompact,
                    onTap: () =>
                        Navigator.of(context).pushNamed('/operator/login'),
                  ),
                  SizedBox(height: isCompact ? 14 : 20),
                  // Warga card (kartu outline biru muda)
                  _RoleCard(
                    key: const Key('role-selection-resident'),
                    title: 'Saya Warga',
                    description: 'Ikuti tugas kesiapan banjir di RT Anda',
                    icon: Icons.home_outlined,
                    actionLabel: 'MASUK DENGAN KODE RT',
                    isPrimary: false,
                    isCompact: isCompact,
                    onTap: () =>
                        Navigator.of(context).pushNamed('/resident/entry'),
                  ),
                  SizedBox(height: isCompact ? 24 : 32),
                  // Darurat button (outline merah penuh lebar)
                  OutlinedButton.icon(
                    key: const Key('emergency-directory-entry'),
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/emergency'),
                    icon: const Icon(
                      Icons.health_and_safety_outlined,
                      size: 20,
                    ),
                    label: const Text('Darurat'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.appColors.danger,
                      side: BorderSide(color: context.appColors.danger),
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  SizedBox(height: isCompact ? 16 : 24),
                  // Akses Pengujian Juri / Mode Demo Mandiri
                  Container(
                    key: const Key('demo-eval-card'),
                    padding: EdgeInsets.all(isCompact ? 10 : 12),
                    decoration: BoxDecoration(
                      color: context.appColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.appColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              color: context.appColors.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Akses Cepat Pengujian Juri',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: context.appColors.primaryDark,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          key: const Key('quick-demo-operator'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(40),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed(
                              '/operator/home',
                              arguments: OperatorProfile(
                                uid: 'op-demo-rt01',
                                communityId: 'rt-01-demo',
                                displayName: 'Ketua RT 01 Kedungwaru',
                                role: OperatorRole.ketuaRtRw,
                                rtLabel: 'RT 01 / RW 02 Kedungwaru',
                                communityName: 'Demo RT 01 / RW 02 Kedungwaru',
                              ),
                            );
                          },
                          child: const Text(
                            'Masuk Demo Ketua RT',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: const Key('quick-demo-resident'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(40),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed(
                              '/resident/home',
                              arguments: ResidentSession(
                                residentId: 'res-budi-01',
                                communityId: 'rt-01-demo',
                                communityName: 'Demo RT 01 / RW 02 Kedungwaru',
                                rtLabel: 'RT 01 / RW 02 Kedungwaru',
                                nickname: 'Budi (Juri)',
                                expiresAt: DateTime.now().add(
                                  const Duration(days: 30),
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'Masuk Demo Warga',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isCompact ? 16 : 24),
                  // Disclaimer + tagline aplikasi
                  Container(
                    padding: EdgeInsets.all(isCompact ? 12 : 16),
                    decoration: BoxDecoration(
                      color: GuyubTokens.greyFill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Kesiapsiagaan banjir bersama warga',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Guyub.id membantu koordinasi persiapan. Aplikasi ini bukan '
                          'prediksi banjir tingkat RT atau pengganti layanan darurat resmi.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ResumeSessionCard extends StatelessWidget {
  const _ResumeSessionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primarySoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.primary, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sesi Aktif Ditemukan',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryDark,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 16, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu besar untuk role selection (meniru proposal Figma).
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.actionLabel,
    required this.isPrimary,
    required this.isCompact,
    required this.onTap,
    this.semanticTitle,
    super.key,
  });

  final String title;

  /// Label aksesibilitas penuh bila berbeda dari judul visual.
  final String? semanticTitle;
  final String description;
  final IconData icon;
  final String actionLabel;
  final bool isPrimary;
  final bool isCompact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bgColor = isPrimary ? GuyubTokens.heroBlue : Colors.white;
    final titleColor = isPrimary ? Colors.white : colors.primary;
    final bodyColor = isPrimary
        ? Colors.white.withValues(alpha: 0.92)
        : colors.textSecondary;
    final footerColor = isPrimary ? Colors.white : colors.textSecondary;

    final titleText = Text(
      title,
      style: TextStyle(
        color: titleColor,
        fontWeight: FontWeight.w700,
        fontSize: isCompact ? 17 : 19,
      ),
    );

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            18,
            isCompact ? 16 : 20,
            18,
            isCompact ? 14 : 18,
          ),
          decoration: BoxDecoration(
            border: isPrimary
                ? null
                : Border.all(color: GuyubTokens.wargaHeroBorder, width: 1.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ikon pada kotak semi-transparan
                  Container(
                    width: isCompact ? 44 : 50,
                    height: isCompact ? 44 : 50,
                    decoration: BoxDecoration(
                      color: isPrimary
                          ? Colors.white.withValues(alpha: 0.25)
                          : GuyubTokens.templateFill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      size: isCompact ? 24 : 28,
                      color: isPrimary ? Colors.white : colors.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (semanticTitle case final label?)
                          Semantics(
                            label: label,
                            child: ExcludeSemantics(child: titleText),
                          )
                        else
                          titleText,
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            color: bodyColor,
                            fontSize: isCompact ? 12 : 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: isCompact ? 24 : 36),
              // Footer aksi
              Row(
                children: [
                  Flexible(
                    child: Text(
                      actionLabel,
                      style: TextStyle(
                        color: footerColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: footerColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
