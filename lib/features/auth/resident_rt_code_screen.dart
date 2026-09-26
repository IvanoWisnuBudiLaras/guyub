import 'package:flutter/material.dart';
import '../../data/fake/fake_auth_repository.dart';
import '../../data/local/session_storage.dart';
import '../../domain/models/app_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../shared/widgets/primary_button.dart';
import '../shell/app_shell.dart';

/// Form masuk Warga dengan kode RT — tanpa akun formal (PRD §5/§13).
/// TODO(integrasi): ganti `_authRepository` dengan implementasi asli yang
/// manggil RT-code validation endpoint punya Hysan67.
class ResidentRtCodeScreen extends StatefulWidget {
  const ResidentRtCodeScreen({super.key});

  @override
  State<ResidentRtCodeScreen> createState() => _ResidentRtCodeScreenState();
}

class _ResidentRtCodeScreenState extends State<ResidentRtCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  // TODO(integrasi): swap ke implementasi asli dari Hysan67.
  final AuthRepository _authRepository = FakeAuthRepository();
  final SessionStorage _sessionStorage = SecureSessionStorage();

  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final session = await _authRepository.joinWithRtCode(
        _codeController.text.trim(),
      );
      await _sessionStorage.save(session);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell(role: UserRole.resident)),
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
      appBar: AppBar(title: const Text('Masuk dengan Kode RT')),
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
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Kode RT',
                  hintText: 'cth. RT03RW07-XXXX',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Masukkan kode RT yang diberikan Ketua RT'
                    : null,
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Masuk dengan Kode RT',
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
