-- 000_missing_base_schema.sql
-- ==========================================================================
-- ملف تعويضي — يعيد بناء الأساس المفقود من migration قديم اسمه "002"
-- (اتعمل على قاعدة الاختبار في مرحلة تطوير قديمة، قبل ما تبدأ مراجعة
-- الأمان دي، ومفيش نسخة منه في الريبو). بعض الجداول على قاعدة الإنتاج
-- ناقصة تمامًا، وبعضها موجود لكن بأعمدة أقل من اللي التطبيق محتاجه
-- (اتأكد ده فعليًا: admin_notifications موجود بس بـ 4 أعمدة فقط).
--
-- عشان كده كل جدول هنا بنمط مزدوج:
--   1) CREATE TABLE IF NOT EXISTS بكل الأعمدة (لو الجدول مش موجود خالص)
--   2) ALTER TABLE ADD COLUMN IF NOT EXISTS لكل عمود لوحده بعدها
--      (لو الجدول كان موجود جزئياً، الخطوة دي بتضيف الناقص حتى لو
--      CREATE اتجاهل بالكامل لأن الجدول "موجود")
--
-- ده يضمن الملف يشتغل صح في الحالات التلاتة: جدول مش موجود، جدول
-- موجود ناقص أعمدة، جدول موجود كامل بالفعل.
--
-- شغّله على قاعدة الإنتاج **قبل** 001، وهو أول ملف في الترتيب.
-- آمن يتكرر بالكامل.
-- ==========================================================================

-- 1) أعمدة ناقصة على inventory_items (غير اللي بتضيفها 003/007)
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS ownership_status VARCHAR(20) DEFAULT 'Owned';

-- 2) أعمدة ناقصة على users — نظام الصلاحيات كله بيعتمد عليها
ALTER TABLE users ADD COLUMN IF NOT EXISTS can_export BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS can_track BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS can_edit BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'Active';
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_by TEXT;

-- 3) أعمدة ناقصة على specs_knowledge_base
ALTER TABLE specs_knowledge_base ADD COLUMN IF NOT EXISTS "Part_Model" TEXT;
ALTER TABLE specs_knowledge_base ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ DEFAULT now();

-- 4) عمود ناقص على transactions_log — الصرف محتاجه أساساً
ALTER TABLE transactions_log ADD COLUMN IF NOT EXISTS exit_type TEXT;

-- 5) جدول الإشعارات — موجود جزئياً على الإنتاج (4 أعمدة بس، ناقصه
-- notif_type وrelated_id اللي كل كود الإشعارات الجديد بيعتمد عليهم)
CREATE TABLE IF NOT EXISTS admin_notifications (
    notif_id BIGSERIAL PRIMARY KEY,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    timestamp TIMESTAMPTZ DEFAULT now(),
    notif_type TEXT,
    related_id INT
);
ALTER TABLE admin_notifications ADD COLUMN IF NOT EXISTS notif_type TEXT;
ALTER TABLE admin_notifications ADD COLUMN IF NOT EXISTS related_id INT;
CREATE INDEX IF NOT EXISTS idx_admin_notifications_timestamp ON admin_notifications(timestamp);

-- 6) إعدادات تفعيل/إيقاف كل نوع إشعار لوحده
CREATE TABLE IF NOT EXISTS notification_settings (
    notif_type TEXT PRIMARY KEY,
    enabled BOOLEAN NOT NULL DEFAULT true
);

-- 7) طلبات الموافقة المعلّقة (تعديل رقم قطعة/سريال، استيراد قاعدة معرفة)
CREATE TABLE IF NOT EXISTS pending_approvals (
    id BIGSERIAL PRIMARY KEY,
    approval_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    requested_by TEXT,
    status TEXT NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMPTZ DEFAULT now(),
    resolved_by TEXT,
    resolved_at TIMESTAMPTZ
);
ALTER TABLE pending_approvals ADD COLUMN IF NOT EXISTS requested_by TEXT;
ALTER TABLE pending_approvals ADD COLUMN IF NOT EXISTS resolved_by TEXT;
ALTER TABLE pending_approvals ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_pending_approvals_status ON pending_approvals(status);

-- 8) استعلامات المهندسين — موجود على الإنتاج، لسه ما اتأكدناش من كل
-- أعمدته، فمضاف كل عمود بالنمط المزدوج احتياطاً.
CREATE TABLE IF NOT EXISTS engineer_queries (
    query_id BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    part_number TEXT NOT NULL,
    part_category TEXT,
    part_description TEXT,
    query_reason TEXT,
    requested_by TEXT,
    target_device TEXT,
    merchant_name TEXT,
    merchant_phone TEXT,
    comments TEXT,
    status TEXT DEFAULT 'Pending',
    timestamp TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE engineer_queries ADD COLUMN IF NOT EXISTS part_category TEXT;
ALTER TABLE engineer_queries ADD COLUMN IF NOT EXISTS part_description TEXT;
ALTER TABLE engineer_queries ADD COLUMN IF NOT EXISTS query_reason TEXT;
ALTER TABLE engineer_queries ADD COLUMN IF NOT EXISTS requested_by TEXT;
ALTER TABLE engineer_queries ADD COLUMN IF NOT EXISTS target_device TEXT;
ALTER TABLE engineer_queries ADD COLUMN IF NOT EXISTS merchant_name TEXT;
ALTER TABLE engineer_queries ADD COLUMN IF NOT EXISTS merchant_phone TEXT;
ALTER TABLE engineer_queries ADD COLUMN IF NOT EXISTS comments TEXT;
ALTER TABLE engineer_queries ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'Pending';
CREATE INDEX IF NOT EXISTS idx_engineer_queries_part_number ON engineer_queries(part_number);
CREATE INDEX IF NOT EXISTS idx_engineer_queries_timestamp ON engineer_queries(timestamp);

-- 9) نسخة احتياطية من قاعدة المعرفة قبل كل استيراد جديد
CREATE TABLE IF NOT EXISTS kb_import_backups (
    id BIGSERIAL PRIMARY KEY,
    snapshot JSONB NOT NULL,
    created_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 10) تخصيص ظهور التبويبات لكل مستخدم لوحده
CREATE TABLE IF NOT EXISTS user_tab_overrides (
    username TEXT NOT NULL,
    tab_id TEXT NOT NULL,
    enabled BOOLEAN NOT NULL,
    updated_by TEXT,
    updated_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (username, tab_id)
);
