import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/asj_logo.dart';
import 'auth_providers.dart';

/// شاشة دخول بأسلوب مبسّط شبيه بتطبيقات التواصل الاجتماعي الكبيرة
/// (لوجو كبير في المنتصف أعلى الشاشة، حقول مرتفعة بحواف دائرية،
/// زر دخول كبير بعرض الشاشة، رابط استرجاع كلمة المرور أسفله).
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

  void _showForgotPasswordNotice() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('نسيت كلمة المرور؟'),
        content: const Text(
          'تواصل مع مسؤول النظام (الأدمن) لإعادة تعيين كلمة المرور.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
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
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(flex: 3),
                        const _BrandHeader(),
                        const Spacer(flex: 2),
                        _RoundedField(
                          controller: _usernameController,
                          hint: 'اسم المستخدم',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 14),
                        _RoundedField(
                          controller: _passwordController,
                          hint: 'كلمة المرور',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          onSubmitted: (_) => _submit(),
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.grey.shade600,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
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
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('دخول'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: _showForgotPasswordNotice,
                            child: Text(
                              'نسيت كلمة المرور؟',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'الحسابات تُنشأ عبر مسؤول النظام فقط',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// رأس الشاشة: اللوجو + اسم النظام، بأسلوب "وردمارك" كبير في المنتصف
/// (زي واجهات فيسبوك/انستجرام). استبدل الأيقونة داخل Container بصورة
/// اللوجو الحقيقي بمجرد توفرها:
///   Image.asset('assets/logo.png', width: 96, height: 96)
/// (لا تنسَ إضافة المسار تحت flutter/assets في pubspec.yaml).
/// نفس هيدر النسخة الأصلية (views/base.py -> render_header) بالضبط:
/// نفس اللوجو المرسوم، نفس العنوان، نفس النص الفرعي، مع خط سماوي سفلي
/// يحاكي `border-bottom: 3px solid #00D2FF` من style.css الأصلي.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 18),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AsjLogoPainter.pulseColor, width: 3),
        ),
      ),
      child: Column(
        children: [
          const AsjLogo(size: 90),
          const SizedBox(height: 10),
          Text(
            'ASJ MEDICAL SYSTEMS STORE',
            style: TextStyle(
              fontSize: 22,
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
      ),
    );
  }
}

/// حقل إدخال بأسلوب "بيضاوي" مرتفع بخلفية رمادية فاتحة بدون حدود بارزة،
/// نفس روح حقول تسجيل الدخول في تطبيقات زي فيسبوك.
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
        fillColor: const Color(0xFFF0F2F5),
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
          borderSide: BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
      validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
    );
  }
}
