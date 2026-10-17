import 'package:flutter/material.dart';

import '../../../../core/widgets/app_logo.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/operator_auth_boundary.dart';
import '../../application/operator_profile.dart';

/// Email/password entry for an operator with a server-provisioned RT membership.
final class OperatorLoginScreen extends StatefulWidget {
  const OperatorLoginScreen({
    required this.authBoundary,
    required this.onAuthenticated,
    super.key,
  });

  final OperatorAuthBoundary? authBoundary;
  final ValueChanged<OperatorProfile> onAuthenticated;

  @override
  State<OperatorLoginScreen> createState() => _OperatorLoginScreenState();
}

final class _OperatorLoginScreenState extends State<OperatorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final boundary = widget.authBoundary;
    if (boundary == null) return;
    final result = await boundary.restoreCurrentSession();
    if (!mounted) return;
    result.when(ok: widget.onAuthenticated, err: (_) {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final boundary = widget.authBoundary;
    if (boundary == null) {
      setState(() {
        _errorMessage =
            'Layanan masuk operator belum tersedia. Coba lagi saat tersambung.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final result = await boundary.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    result.when(
      ok: widget.onAuthenticated,
      err: (error) => setState(() => _errorMessage = error.userMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 700;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
                    title: 'Masuk sebagai Ketua RT/RW',
                    isCompact: isCompact,
                  ),
                  SizedBox(height: isCompact ? 24 : 32),
                  // Email field
                  TextFormField(
                    key: const Key('operator-email'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'nama@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Masukkan email.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  // Password field dengan toggle visibility
                  TextFormField(
                    key: const Key('operator-password'),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Kata sandi',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Masukkan kata sandi.'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  // Error message
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.appColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: context.appColors.danger.withValues(alpha: 0.3),
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
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: context.appColors.danger,
                                  fontSize: 14,
                                ),
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
                        : const Text('Masuk'),
                  ),
                  SizedBox(height: isCompact ? 16 : 24),
                  // Help text
                  Container(
                    padding: EdgeInsets.all(isCompact ? 12 : 16),
                    decoration: BoxDecoration(
                      color: context.appColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.appColors.border),
                    ),
                    child: Text(
                      'Akun operator harus terdaftar pada komunitas RT. '
                      'Warga tidak menggunakan akun operator.',
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
