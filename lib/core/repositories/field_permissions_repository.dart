import 'package:supabase_flutter/supabase_flutter.dart';

/// نظام التحكم في ظهور العناصر الداخلية جوه ٥ تبويبات بس (تسجيل قطعة،
/// المخزون، لوحة التعديل، التصدير، تحليل البيانات)، لكل حساب لوحده.
/// كل تبويب ليه "كتالوج" ثابت من العناصر القابلة للتحكم (field_key ->
/// اسم عربي للعرض في شاشة تعديل المستخدم)، والقيمة الفعلية بتتخزن في
/// جدول user_field_overrides. الافتراضي (لو مفيش صف محفوظ) هو "ظاهر"
/// — يعني الأدمن بيقفل عناصر بالاستثناء، مش بيفتحها بالاستثناء.
///
/// لإضافة تبويب سادس أو عنصر جديد لتبويب موجود لاحقاً، هنا بس المكان
/// اللي يتعدّل — مفيش أي تغيير في الجدول أو بنية الكود مطلوب.
class FieldPermissionsRepository {
  final _client = Supabase.instance.client;

  static const Map<String, Map<String, String>> tabFields = {
    'entry': {
      'part_number': 'رقم القطعة',
      'part_model': 'الموديل (الاسم الكودي)',
      'serial_number': 'الرقم التسلسلي (Serial)',
      'brand': 'الماركة',
      'category': 'الوصف/الفئة',
      'compatible_model': 'الجهاز المتوافق',
      'additional_compat': 'أجهزة متوافقة إضافية',
      'market_value': 'تقدير السعر',
      'insights': 'ملاحظات فنية',
    },
    'inventory_summary': {
      'barcode_search': 'زرار البحث بالباركود',
      'filter_sort_button': 'زرار الفلاتر والترتيب (⚙️)',
      'individual_view': 'خيار العرض "فردية"',
      'market_value': 'السعر التقريبي (تفاصيل القطعة)',
      'edit_button': 'زرار "تعديل البيانات"',
      'dispatch_button': 'زرار "صرف/استرجاع"',
      'track_button': 'زرار "تتبع"',
      'location_field': 'حقل الموقع',
    },
    'edit_dashboard': {
      'part_number_edit': 'تعديل رقم القطعة',
      'serial_edit': 'تعديل الرقم التسلسلي',
      'location': 'الموقع',
      'condition': 'الحالة الفنية',
      'status': 'الحالة',
      'ownership': 'حالة الملكية',
      'brand': 'البراند',
      'category': 'الفئة/الوصف',
      'compatible_model': 'الجهاز المتوافق',
      'additional_compat': 'أجهزة متوافقة إضافية',
      'market_value': 'السعر التقريبي',
      'insights': 'ملاحظات فنية',
      'photo_reanalyze': 'إعادة تحليل بصورة',
      'return_button': 'استرجاع القطعة للمخزون',
    },
    'export': {
      'full_inventory': 'المخزون الكامل',
      'available': 'المتاح فقط',
      'dispatched': 'المصروف',
      'kb': 'قاعدة المعرفة',
      'log': 'سجل الحركات',
    },
    'analytics': {
      'stat_totals': 'أرقام سريعة',
      'status_chart': 'توزيع حالة المخزون',
      'ownership_chart': 'الصيانة/الأمانة الآن',
      'exit_reason_chart': 'سبب الصرف',
      'trend_chart': 'اتجاه الصرف',
      'top_parts_chart': 'أكتر القطع صرفاً',
      'engineer_leaderboard_chart': 'أداء صرف المهندسين',
      'pivot_builder': 'بناء تحليل حر (الجزء العام)',
    },
  };

  /// أسماء التبويبات الخمسة (للعرض في الـ dropdown بشاشة تعديل المستخدم).
  static const Map<String, String> controllableTabLabels = {
    'entry': 'تسجيل قطعة',
    'inventory_summary': 'المخزون',
    'edit_dashboard': 'لوحة التعديل',
    'export': 'التصدير',
    'analytics': 'تحليل البيانات',
  };

  /// كل التخصيصات المحفوظة لتبويب معين لحساب معين — Map من field_key
  /// لـ true/false. أي مفتاح مش موجود فيها معناه "ظاهر" (الافتراضي).
  Future<Map<String, bool>> getOverrides(String username, String tabId) async {
    final rows = await _client
        .from('user_field_overrides')
        .select('field_key, visible')
        .eq('username', username)
        .eq('tab_id', tabId);
    return {
      for (final r in rows as List) r['field_key'] as String: r['visible'] as bool,
    };
  }

  /// كل التخصيصات المحفوظة لحساب معين عبر كل التبويبات الخمسة مع
  /// بعض — مفيدة لصفحة تعديل المستخدم عشان تحمّلهم كلهم بطلب واحد.
  Future<Map<String, Map<String, bool>>> getAllOverridesForUser(String username) async {
    final rows = await _client
        .from('user_field_overrides')
        .select('tab_id, field_key, visible')
        .eq('username', username);
    final result = <String, Map<String, bool>>{};
    for (final r in rows as List) {
      final tabId = r['tab_id'] as String;
      result.putIfAbsent(tabId, () => {});
      result[tabId]![r['field_key'] as String] = r['visible'] as bool;
    }
    return result;
  }

  Future<void> setOverride({
    required String username,
    required String tabId,
    required String fieldKey,
    required bool visible,
    required String updatedBy,
  }) async {
    await _client.from('user_field_overrides').upsert({
      'username': username,
      'tab_id': tabId,
      'field_key': fieldKey,
      'visible': visible,
      'updated_by': updatedBy,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> clearOverride({
    required String username,
    required String tabId,
    required String fieldKey,
  }) async {
    await _client
        .from('user_field_overrides')
        .delete()
        .eq('username', username)
        .eq('tab_id', tabId)
        .eq('field_key', fieldKey);
  }

  /// الافتراضي "ظاهر" لو مفيش تخصيص محفوظ — الأدمن بيقفل عناصر
  /// بالاستثناء (Deny-list)، مش بيفتحها بالاستثناء.
  static bool isVisible(Map<String, bool> overrides, String fieldKey) =>
      overrides[fieldKey] ?? true;
}