/// تطابق حرفي لـ core/enums.py في النظام الأصلي (Streamlit) — نفس القيم
/// النصية بالضبط لأنها مخزنة كـ String في القاعدة، مش Enum حقيقي في Postgres.
library;

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

/// حالة ملكية القطعة وقت الإدخال (عمود جديد: ownership_status).
enum OwnershipStatus {
  owned('Owned', 'ملك لينا'),
  maintenance('Maintenance', 'صيانة'),
  custody('Custody', 'أمانة'),
  trial('Trial', 'تجربة');

  const OwnershipStatus(this.dbValue, this.arabicLabel);
  final String dbValue;
  final String arabicLabel;

  static OwnershipStatus fromDb(String? value) => OwnershipStatus.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => OwnershipStatus.owned,
      );
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
  return_('RETURN', 'استرجاع'),
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

/// سبب صرف القطعة — عمود exit_type الجديد في transactions_log (راجع
/// migrations/002_add_exit_type.sql). يُستخدم في تحليل البيانات لعرض
/// توزيع الصرف حسب السبب.
enum ExitType {
  sale('Sale', 'بيع'),
  loan('Loan', 'إعارة مؤقت'),
  damaged('Damaged', 'تالف');

  const ExitType(this.dbValue, this.arabicLabel);
  final String dbValue;
  final String arabicLabel;

  static ExitType fromDb(String? value) => ExitType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => ExitType.sale,
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

/// نوع الإدخال: قطعة غيار عادية أو عدة/معدة شغل (عمود entry_type الجديد).
enum EntryType {
  part('Part', 'قطعة'),
  equipment('Equipment', 'معدة شغل');

  const EntryType(this.dbValue, this.arabicLabel);
  final String dbValue;
  final String arabicLabel;

  static EntryType fromDb(String? value) => EntryType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => EntryType.part,
      );
}

/// نوع طلب الموافقة المعلّق (جدول pending_approvals الجديد).
enum ApprovalType {
  partNumberEdit('part_number_edit', 'تعديل رقم القطعة'),
  serialEdit('serial_edit', 'تعديل الرقم التسلسلي'),
  kbImport('kb_import', 'استيراد قاعدة المعرفة');

  const ApprovalType(this.dbValue, this.arabicLabel);
  final String dbValue;
  final String arabicLabel;

  static ApprovalType fromDb(String? value) => ApprovalType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => ApprovalType.partNumberEdit,
      );
}

enum ApprovalStatus {
  pending('Pending', 'قيد الانتظار'),
  approved('Approved', 'تمت الموافقة'),
  rejected('Rejected', 'مرفوض');

  const ApprovalStatus(this.dbValue, this.arabicLabel);
  final String dbValue;
  final String arabicLabel;

  static ApprovalStatus fromDb(String? value) => ApprovalStatus.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => ApprovalStatus.pending,
      );
}

/// أنواع أحداث الإشعارات — الجولة الثالثة (نقطة ١١): بدل ٤ أنواع ثابتة
/// بس، القايمة دلوقتي بتغطي كل حدث حقيقي في النظام، كل واحد قابل
/// للتشغيل/الإيقاف لوحده من notification_settings. القيم دي هي نفسها
/// notif_type المُستخدمة في NotificationRepository.create/getAllSettings.
///
/// ملحوظة: مفيش نوع عام "approval_created" — الثلاثة أنواع طلبات
/// الموافقة (تعديل رقم قطعة/سريال/استيراد قاعدة معرفة) بترسل إشعارها
/// الخاص المحدد لحظة إنشاء الطلب نفسه (part_number_edit/serial_edit/
/// kb_import)، فنوع عام إضافي هيبقى تكرار مالوش استخدام حقيقي.
/// approval_resolved هو النوع العام الصحيح — بيغطي لحظة الحسم (قبول/
/// رفض) بغض النظر عن نوع الطلب.
enum NotificationEventType {
  partEntry('part_entry', 'تسجيل قطعة جديدة'),
  dispatch('dispatch', 'صرف قطعة'),
  returnToStock('return', 'استرجاع للمخزون'),
  partNumberEdit('part_number_edit', 'تعديل رقم القطعة'),
  serialEdit('serial_edit', 'تعديل الرقم التسلسلي'),
  newQuery('new_query', 'استعلام/بحث جديد'),
  kbImport('kb_import', 'استيراد قاعدة معرفة'),
  kbExport('kb_export', 'تصدير قاعدة معرفة'),
  login('login', 'تسجيل دخول'),
  sessionEnd('session_end', 'انتهاء جلسة'),
  userCreated('user_created', 'إنشاء حساب مستخدم'),
  permissionsChanged('permissions_changed', 'تعديل صلاحيات مستخدم'),
  adminPasswordReset('admin_password_reset', 'إعادة تعيين كلمة مرور (أدمن)'),
  selfPasswordChange('self_password_change', 'تغيير كلمة مرور شخصي'),
  approvalResolved('approval_resolved', 'الرد على طلب موافقة'),
  fieldUpdate('field_update', 'تعديل بيانات أساسية لقطعة');

  const NotificationEventType(this.dbValue, this.arabicLabel);
  final String dbValue;
  final String arabicLabel;

  static NotificationEventType fromDb(String? value) =>
      NotificationEventType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => NotificationEventType.partEntry,
      );
}

/// تجميع منطقي لأنواع الإشعارات لعرضها كقوائم مجمّعة/منسدلة بدل قايمة
/// مسطحة طويلة (طلب الجولة الثالثة: "شكل لطيف").
const Map<String, List<NotificationEventType>> notificationEventGroups = {
  'المخزون والقطع': [
    NotificationEventType.partEntry,
    NotificationEventType.dispatch,
    NotificationEventType.returnToStock,
    NotificationEventType.partNumberEdit,
    NotificationEventType.serialEdit,
    NotificationEventType.fieldUpdate,
  ],
  'البحث والاستعلام': [
    NotificationEventType.newQuery,
  ],
  'قاعدة المعرفة': [
    NotificationEventType.kbImport,
    NotificationEventType.kbExport,
  ],
  'الحسابات والجلسات': [
    NotificationEventType.login,
    NotificationEventType.sessionEnd,
    NotificationEventType.userCreated,
    NotificationEventType.permissionsChanged,
    NotificationEventType.adminPasswordReset,
    NotificationEventType.selfPasswordChange,
  ],
  'الموافقات': [
    NotificationEventType.approvalResolved,
  ],
};