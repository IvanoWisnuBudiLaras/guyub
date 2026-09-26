import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../application/auth_controller.dart';

/// Form login Ketua RT/RW. Panggil [AuthController.signInOperator] dari application layer.
class OperatorLoginScreen extends StatefulWidget {
  const OperatorLoginScreen({super.key});

  @override
  State<OperatorLoginScreen> createState() => _OperatorLoginScreenState();
}

class _OperatorLoginScreenState extends State<OperatorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // TODO(integrasi): AuthController dipanggil di sini untuk autentikasi operator Firebase Auth.
    final authController = context.read<AuthController>();
    final success = await authController.signInOperator(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/shell',
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthController>().state;

    return Scaffold(
      appBar: AppBar(title: const Text('Masuk sebagai Ketua RT/RW')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (authState.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.dangerRed, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          authState.errorMessage!,
                          style: const TextStyle(color: AppColors.dangerRed, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'nama@domain.com',
                ),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Masukkan email yang valid'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Kata Sandi',
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Kata sandi tidak boleh kosong'
                    : null,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Fitur Lupa Kata Sandi dapat diakses melalui tim pendamping RT atau admin sistem.',
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Lupa kata sandi?',
                    style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Masuk',
                isLoading: authState.isBusy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
