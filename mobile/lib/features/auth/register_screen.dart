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

/// Registration screen. On success the router redirect sends the new user
/// to `/lobby`.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  static const path = '/register';

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
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
      await ref.read(authRepositoryProvider).register(
            email: _emailCtrl.text.trim(),
            username: _usernameCtrl.text.trim(),
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
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _validateUsername(String? v) {
    if (v == null || v.isEmpty) return 'กรุณากรอกชื่อผู้ใช้';
    if (v.length < 3) return 'ต้องมีอย่างน้อย 3 ตัวอักษร';
    if (v.length > 20) return 'ต้องไม่เกิน 20 ตัวอักษร';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
      return 'ใช้ได้เฉพาะตัวอักษร ตัวเลข และขีดล่าง';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'กรุณากรอกรหัสผ่าน';
    if (v.length < 8) return 'ต้องมีอย่างน้อย 8 ตัวอักษร';
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.isEmpty) return 'กรุณากรอกอีเมล';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      return 'รูปแบบอีเมลไม่ถูกต้อง';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AuthGameShell(
      title: 'สมัครเล่นออโต้เชส',
      subtitle: 'สร้างโปรไฟล์ผู้บัญชาการของคุณ',
      showBack: true,
      onBack: _loading
          ? null
          : () => context.canPop() ? context.pop() : context.go('/login'),
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
                validator: _validateEmail,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _usernameCtrl,
                label: 'ชื่อผู้ใช้',
                helperText: '3–20 ตัวอักษร ใช้ตัวอักษร ตัวเลข หรือขีดล่าง',
                prefixIcon: Icons.person_outline,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
                validator: _validateUsername,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _passwordCtrl,
                label: 'รหัสผ่าน',
                helperText: 'อย่างน้อย 8 ตัวอักษร',
                prefixIcon: Icons.lock_outline,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _submit(),
                validator: _validatePassword,
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
                icon: Icons.shield_outlined,
                child: const Text('สร้างบัญชี'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: _loading
                    ? null
                    : () =>
                        context.canPop() ? context.pop() : context.go('/login'),
                variant: AppButtonVariant.ghost,
                child: const Text('มีบัญชีอยู่แล้ว? เข้าสู่ระบบ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
