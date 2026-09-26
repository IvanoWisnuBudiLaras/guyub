import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../application/auth_controller.dart';

/// Form masuk Warga dengan kode RT — tanpa akun formal (PRD §5/§13).
class ResidentRtCodeScreen extends StatefulWidget {
  const ResidentRtCodeScreen({super.key});

  @override
  State<ResidentRtCodeScreen> createState() => _ResidentRtCodeScreenState();
}

class _ResidentRtCodeScreenState extends State<ResidentRtCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // TODO(integrasi): AuthController dipanggil di sini untuk penukaran kode RT warga.
    final authController = context.read<AuthController>();
    final success = await authController.joinAsResident(_codeController.text);

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
      appBar: AppBar(title: const Text('Masuk dengan Kode RT')),
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
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Kode ini diberikan oleh Ketua RT Anda.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Masuk dengan Kode RT',
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
