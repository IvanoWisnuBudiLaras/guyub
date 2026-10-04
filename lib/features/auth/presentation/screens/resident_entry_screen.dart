import 'package:flutter/material.dart';

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
    } catch (_) {
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
    final controller = widget.controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Akses Warga')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48),
                SizedBox(height: 16),
                Text(
                  'Akses warga belum tersedia',
                  style: TextStyle(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12),
                Text(
                  'Kode RT saja belum cukup untuk melindungi data warga. '
                  'Akses akan tersedia setelah sesi warga yang aman disiapkan.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_restoring) {
      return Scaffold(
        appBar: AppBar(title: const Text('Masuk sebagai Warga')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_restoreUnavailable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Masuk sebagai Warga')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sesi tersimpan belum dapat diverifikasi. Periksa koneksi. '
                  'Data lokal tidak dihapus.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _retryRestore,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Masuk sebagai Warga')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Akses Warga',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text('Masukkan kode RT dan nama panggilan Anda.'),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('resident-join-code'),
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Kode RT',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Kode RT wajib diisi.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('resident-nickname'),
                    controller: _nicknameController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Nama panggilan',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Nama panggilan wajib diisi.'
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('resident-join-submit'),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Masuk ke RT'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Kode RT hanya membuka sesi warga pada komunitas terkait. '
                    'Jangan membagikan kode ke grup publik.',
                    textAlign: TextAlign.center,
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
