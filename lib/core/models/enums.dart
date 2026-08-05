/// تطابق حرفي لـ core/enums.py في النظام الأصلي (Streamlit) — نفس القيم
/// النصية بالضبط لأنها مخزنة كـ String في القاعدة، مش Enum حقيقي في Postgres.

enum ItemStatus {
  available('Available', 'متاح'),
  out('Out', 'صادر'),
  reserved('Reserved', 'محجوز'),
  damaged('Damaged', 'تالف');

  const ItemStatus(this.dbValue, this.arabicLabel);
  final String dbValue;
  final String arabicLabel;

  static ItemStatus fromDb(String? value) => ItemStatus.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => ItemStatus.available,
      );
}

enum ItemCondition {
  newItem('جديدة'),
  used('مستعملة');

  const ItemCondition(this.dbValue);
  final String dbValue;

  static ItemCondition fromDb(String? value) => ItemCondition.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => ItemCondition.used,
      );
}

enum QueryReason {
  inspection('معاينة'),
  merchant('طلب شراء لتاجر'),
  device('مطلوب لجهاز معين'),
  specs('استفسار عن المواصفات');

  const QueryReason(this.dbValue);
  final String dbValue;
}

enum QueryStatus {
  pending('Pending', 'قيد الانتظار'),
  fulfilled('Fulfilled', 'تم التنفيذ'),
  cancelled('Cancelled', 'ملغي');

  const QueryStatus(this.dbValue, this.arabicLabel);
  final String dbValue;
  final String arabicLabel;

  static QueryStatus fromDb(String? value) => QueryStatus.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => QueryStatus.pending,
      );
}

/// أنواع الحركات المسجّلة في transactions_log — تُستخدم أيضاً كأساس
/// لعرض التايم لاين (تتبع القطعة / تتبع المستخدم) لاحقاً في المرحلة 3.
enum ActionType {
  insert('INSERT', 'إضافة'),
  update('UPDATE', 'تعديل'),
  delete('DELETE', 'حذف'),
  out('OUT', 'صرف'),
  search('SEARCH', 'بحث'),
  login('LOGIN', 'دخول'),
  logout('LOGOUT', 'خروج'),
  export_('EXPORT', 'تصدير'),
  import_('IMPORT', 'استيراد'),
  userMgmt('USER_MGMT', 'إدارة مستخدمين'),
  dbRestore('DB_RESTORE', 'استعادة قاعدة بيانات');

  const ActionType(this.dbValue, this.arabicLabel);
  final String dbValue;
  final String arabicLabel;

  static ActionType fromDb(String? value) => ActionType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => ActionType.search,
      );
}

const List<String> defaultItemTypes = [
  'بوردة',
  'أنبوبة أشعة',
  'كابل',
  'حساس',
  'محرك',
  'قطعة أخرى',
];
