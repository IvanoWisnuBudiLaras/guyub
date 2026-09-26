import 'package:flutter/material.dart';
import '../../data/fake/fake_auth_repository.dart';
import '../../data/local/session_storage.dart';
import '../../domain/models/app_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../shared/widgets/primary_button.dart';
import '../shell/app_shell.dart';

/// Form login Ketua RT/RW. Panggil AuthRepository.loginOperator —
/// TODO(integrasi): ganti `_authRepository` dengan implementasi asli
/// (Firebase Auth) begitu Hysan67 selesai, cukup ganti 1 baris di bawah.
class OperatorLoginScreen extends StatefulWidget {
  const OperatorLoginScreen({super.key});

  @override
  State<OperatorLoginScreen> createState() => _OperatorLoginScreenState();
}

class _OperatorLoginScreenState extends State<OperatorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // TODO(integrasi): swap ke implementasi asli dari Hysan67.
  final AuthRepository _authRepository = FakeAuthRepository();
  final SessionStorage _sessionStorage = SecureSessionStorage();

  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final session = await _authRepository.loginOperator(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await _sessionStorage.save(session);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell(role: UserRole.operator)),
        (route) => false,
      );
    } on AuthException catch (e) {
      setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Masuk sebagai Ketua RT/RW')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorText != null) ...[
                Text(_errorText!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Masukkan email yang valid'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Kata Sandi'),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Kata sandi tidak boleh kosong'
                    : null,
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Masuk',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
