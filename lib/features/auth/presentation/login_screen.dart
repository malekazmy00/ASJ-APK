import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/asj_logo.dart';
import 'auth_providers.dart';

/// شاشة الدخول: منطقة بيضا فوق فيها اللوجو والعنوان (زي ما كانت)،
/// وتحتها بطاقة كحلية بحواف علوية دائرية فيها الحقول والزرار — بدل
/// ما تكون الشاشة كلها بيضا. الألوان الثلاثة (أبيض/كحلي/سماوي) هي
/// هوية ASJ الفعلية، مأخوذة من AppColors.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(authControllerProvider.notifier);
    final success = await controller.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? 'حدث خطأ غير متوقع'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
    // التوجيه بعد النجاح يتم تلقائياً عبر go_router (redirect) بمجرد
    // تغيّر authControllerProvider - راجع core/router/app_router.dart
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider.notifier).isLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 28, 24, 8),
                      child: _BrandHeader(),
                    ),
                    Expanded(child: _NavyFormPanel(
                      formKey: _formKey,
                      usernameController: _usernameController,
                      passwordController: _passwordController,
                      obscurePassword: _obscurePassword,
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onSubmit: _submit,
                      isLoading: isLoading,
                    )),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// رأس الشاشة الأبيض: اللوجو الحقيقي + عنوان النظام + النص الفرعي.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AsjLogo(size: 78),
        const SizedBox(height: 12),
        Text(
          'ASJ MEDICAL SYSTEMS STORE',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: AppColors.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'نظام إدارة المستودعات',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// البطاقة الكحلية أسفل الشاشة: خط سماوي فاصل، حقول الدخول، زرار
/// الدخول السماوي، والنص السفلي — كلهم بألوان معدّلة عشان تبان واضحة
/// فوق الخلفية الكحلية.
class _NavyFormPanel extends StatelessWidget {
  const _NavyFormPanel({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.isLoading,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(26, 34, 26, 24),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 28),
            _RoundedField(
              controller: usernameController,
              hint: 'اسم المستخدم',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 14),
            _RoundedField(
              controller: passwordController,
              hint: 'كلمة المرور',
              icon: Icons.lock_outline,
              obscureText: obscurePassword,
              onSubmitted: (_) => onSubmit(),
              suffix: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.grey.shade600,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.primary,
                        ),
                      )
                    : const Text('دخول'),
              ),
            ),
            const SizedBox(height: 16),
            const Spacer(),
            Text(
              'الحسابات تُنشأ عبر مسؤول النظام فقط',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// حقل إدخال أبيض بحواف دائرية — بيبان واضح فوق خلفية البطاقة الكحلية.
class _RoundedField extends StatelessWidget {
  const _RoundedField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffix,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      textAlign: TextAlign.right,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey.shade500),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
    );
  }
}