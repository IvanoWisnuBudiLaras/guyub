import 'package:flutter/material.dart';

import '../../../../core/widgets/app_logo.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/resident_session.dart';
import '../../application/resident_session_controller.dart';

/// RT-code entry remains unavailable unless the scoped backend boundary is wired.
final class ResidentEntryScreen extends StatefulWidget {
  const ResidentEntryScreen({this.controller, this.onAuthenticated, super.key});

  final ResidentSessionController? controller;
  final ValueChanged<ResidentSession>? onAuthenticated;

  @override
  State<ResidentEntryScreen> createState() => _ResidentEntryScreenState();
}

final class _ResidentEntryScreenState extends State<ResidentEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _submitting = false;
  bool _restoring = false;
  bool _restoreUnavailable = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoring = widget.controller != null;
    if (_restoring) _restoreSession();
  }

  Future<void> _restoreSession() async {
    final controller = widget.controller;
    if (controller == null) return;
    try {
      final session = await controller.restoreSession();
      if (mounted && session != null) widget.onAuthenticated?.call(session);
    } catch (_) {
      if (mounted) setState(() => _restoreUnavailable = true);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _retryRestore() async {
    setState(() {
      _restoring = true;
      _restoreUnavailable = false;
    });
    await _restoreSession();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.controller == null || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = await widget.controller!.createSession(
        joinCode: _codeController.text,
        nickname: _nicknameController.text,
      );
      if (mounted) widget.onAuthenticated?.call(session);
    } catch (e, st) {
      debugPrint('[ResidentEntry] createSession gagal: $e\n$st');
      if (mounted) {
        setState(() {
          _error =
              'Kode RT tidak valid atau koneksi tidak tersedia. Coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 700;
    final controller = widget.controller;

    // Screen saat controller belum tersedia
    if (controller == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: context.appColors.textPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: isCompact ? 56 : 72,
                  color: context.appColors.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Akses warga belum tersedia',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Kode RT saja belum cukup untuk melindungi data warga. '
                  'Akses akan tersedia setelah sesi warga yang aman disiapkan.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.appColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loading state saat restore session
    if (_restoring) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: context.appColors.textPrimary,
          elevation: 0,
          title: const Text('Masuk sebagai Warga'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Retry state jika restore gagal
    if (_restoreUnavailable) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: context.appColors.textPrimary,
          elevation: 0,
          title: const Text('Masuk sebagai Warga'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: isCompact ? 56 : 72,
                  color: context.appColors.textSecondary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sesi tersimpan belum dapat diverifikasi. Periksa koneksi. '
                  'Data lokal tidak dihapus.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _retryRestore,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 48),
                  ),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Main entry form
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isCompact ? 16 : 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header dengan logo dan judul
                  _AuthScreenHeader(
                    title: 'Masuk dengan Kode RT',
                    isCompact: isCompact,
                  ),
                  SizedBox(height: isCompact ? 8 : 12),
                  Text(
                    'Masukkan kode RT dan nama panggilan Anda.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: context.appColors.textSecondary),
                  ),
                  SizedBox(height: isCompact ? 24 : 32),
                  // Kode RT field
                  TextFormField(
                    key: const Key('resident-join-code'),
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Kode RT',
                      hintText: 'Contoh: RT001JKT',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Kode RT wajib diisi.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  // Nama panggilan field
                  TextFormField(
                    key: const Key('resident-nickname'),
                    controller: _nicknameController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Nama panggilan',
                      hintText: 'Contoh: Budi',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Nama panggilan wajib diisi.'
                        : null,
                  ),
                  // Error message
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.appColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: context.appColors.danger.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: context.appColors.danger,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: context.appColors.danger,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Submit button
                  FilledButton(
                    key: const Key('resident-join-submit'),
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Gabung'),
                  ),
                  SizedBox(height: isCompact ? 16 : 24),
                  // Privacy info
                  Container(
                    padding: EdgeInsets.all(isCompact ? 12 : 16),
                    decoration: BoxDecoration(
                      color: context.appColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.appColors.border),
                    ),
                    child: Text(
                      'Kode RT hanya membuka sesi warga pada komunitas terkait. '
                      'Jangan membagikan kode ke grup publik.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
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

/// Shared header untuk auth screens dengan logo dan judul.
class _AuthScreenHeader extends StatelessWidget {
  const _AuthScreenHeader({required this.title, required this.isCompact});

  final String title;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(child: AppLogo(size: isCompact ? 56 : 72)),
        SizedBox(height: isCompact ? 12 : 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
