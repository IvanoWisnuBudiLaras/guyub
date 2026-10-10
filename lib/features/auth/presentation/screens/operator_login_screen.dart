import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Masuk Operator RT/RW')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Akun operator harus terdaftar pada komunitas RT. '
                  'Warga tidak menggunakan akun operator.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('operator-email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Masukkan email.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('operator-password'),
                  controller: _passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Kata sandi',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Masukkan kata sandi.'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const CircularProgressIndicator()
                      : const Text('Masuk'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
