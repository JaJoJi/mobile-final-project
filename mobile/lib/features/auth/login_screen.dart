import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/fantasy_page.dart';
import 'auth_game_shell.dart';

/// First screen the user sees. After a successful login the router's
/// redirect (driven by [AuthGate]) sends the user to `/lobby`.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const path = '/login';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  String? _error;
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).login(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      AuthGate.instance.signalSignedIn();
      if (!mounted) return;
      context.go('/lobby');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthGameShell(
      title: 'ออโต้เชส',
      subtitle: 'เข้าสู่ระบบเพื่อกลับสู่สนามแข่งขัน',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                controller: _emailCtrl,
                label: 'อีเมล',
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'กรุณากรอกอีเมล';
                  if (!v.contains('@')) return 'รูปแบบอีเมลไม่ถูกต้อง';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _passwordCtrl,
                label: 'รหัสผ่าน',
                prefixIcon: Icons.lock_outline,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'กรุณากรอกรหัสผ่าน';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                FantasyErrorBanner(message: _error!),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                onPressed: _loading ? null : _submit,
                loading: _loading,
                size: AppButtonSize.lg,
                icon: Icons.login,
                child: const Text('เข้าสู่ระบบ'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: _loading ? null : () => context.push('/register'),
                variant: AppButtonVariant.ghost,
                child: const Text('ยังไม่มีบัญชี? สมัครสมาชิก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
