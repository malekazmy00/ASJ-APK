import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'barcode_scanner_page.dart';

/// خانة بحث بشكل اقتراحات جوجل (Autocomplete) — الجولة الثالثة (نقطة
/// ١٥ و١٨): وانت بتكتب، بتظهر قايمة اقتراحات نصية بس تحت الخانة
/// مباشرة (Inline، مش Overlay طايرة، عشان نتجنب أي باج تموضع زي اللي
/// اتصلح قبل كده في الـ Dialogs) وبتتقلص مع كل حرف — **من غير أي بحث
/// فعلي لسه**. البحث الحقيقي بيحصل بس لما تدوس على اقتراح من القايمة،
/// وقتها [onSelected] بتتنادى بالنص اللي اخترته.
///
/// نفس الودجت دي بتتستخدم في كل الشاشات اللي فيها بحث (تتبع قطعة،
/// المخزون، بحث المهندس، الاستيكرات) — منطق واحد، شكل واحد، بدل ما كل
/// شاشة تعمل نسختها الخاصة.
class AutocompleteSearchField extends StatefulWidget {
  const AutocompleteSearchField({
    super.key,
    required this.hintText,
    required this.fetchSuggestions,
    required this.onSelected,
    this.controller,
    this.showBarcodeButton = true,
    this.onBarcodeScanned,
    this.debounce = const Duration(milliseconds: 300),
  });

  final String hintText;

  /// بيرجع قايمة نصوص الاقتراحات المطابقة جزئياً للنص المكتوب.
  final Future<List<String>> Function(String query) fetchSuggestions;

  /// بتتنادى لما المستخدم يدوس على اقتراح — هنا بس البحث الفعلي بيبدأ.
  final void Function(String selected) onSelected;

  final TextEditingController? controller;
  final bool showBarcodeButton;

  /// لو موجودة، بتتنادى بالكود الممسوح مباشرة بدل ما يتحط في الخانة
  /// وينتظر اقتراحات — الشاشة اللي بتستخدمها هي اللي بتقرر تعمل ايه
  /// (مثلاً تفتح القطعة على طول).
  final Future<void> Function(String code)? onBarcodeScanned;

  final Duration debounce;

  @override
  State<AutocompleteSearchField> createState() => _AutocompleteSearchFieldState();
}

class _AutocompleteSearchFieldState extends State<AutocompleteSearchField> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounceTimer;
  List<String> _suggestions = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    if (widget.controller == null) _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounceTimer = Timer(widget.debounce, () async {
      setState(() => _loading = true);
      final results = await widget.fetchSuggestions(value);
      if (mounted) {
        setState(() {
          _suggestions = results;
          _loading = false;
        });
      }
    });
  }

  void _select(String value) {
    _controller.text = value;
    setState(() => _suggestions = []);
    _focusNode.unfocus();
    widget.onSelected(value);
  }

  Future<void> _scanBarcode() async {
    final code = await scanBarcode(context);
    if (code == null || code.isEmpty) return;
    if (widget.onBarcodeScanned != null) {
      await widget.onBarcodeScanned!(code);
    } else {
      _controller.text = code;
      _onChanged(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search),
            suffixIcon: widget.showBarcodeButton
                ? IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'مسح باركود',
                    onPressed: _scanBarcode,
                  )
                : null,
          ),
          onChanged: _onChanged,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = _suggestions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.north_west, size: 16, color: AppColors.textMuted),
                  title: Text(s, textAlign: TextAlign.right),
                  onTap: () => _select(s),
                );
              },
            ),
          ),
      ],
    );
  }
}