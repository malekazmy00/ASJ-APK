-- 003_round2.sql
-- دفعة التعديلات الكبيرة (جولة تانية بعد اختبار حي) — شغّله يدوياً على
-- Supabase SQL Editor. آمن يتكرر (IF NOT EXISTS في كل حتة).

-- 1) حقول جديدة على القطع: الوصف، الملاحظات، نوع الإدخال
-- (الاسم الكودي/الموديل بتاع القطعة نفسه بيتحط في specs_knowledge_base
-- مش هنا، لأنه صفة لنوع القطعة زي البراند بالظبط، مش لكل وحدة لوحدها)
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS entry_type VARCHAR(20) DEFAULT 'Part';
CREATE INDEX IF NOT EXISTS idx_inventory_entry_type ON inventory_items(entry_type);

-- 1ب) الاسم الكودي/موديل القطعة نفسها في قاعدة المعرفة (نفس مستوى Brand)
ALTER TABLE specs_knowledge_base ADD COLUMN IF NOT EXISTS "Part_Model" TEXT;

-- 1ج) باج قديم اكتشفناه في المراجعة: كل أعمدة specs_knowledge_base
-- بحروف كبيرة ومقتبسة (Part_Number, Brand...) عدا market_value اللي
-- كان بحروف صغيرة، وده كان بيخلي أي حفظ لسعر القطعة من شاشة التعديل
-- أو استيراد CSV يفشل بصمت. توحيد الاسم مع الباقي بدل ما نلاقيه في
-- كل نقطة كتابة في الكود.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'specs_knowledge_base' AND column_name = 'market_value'
  ) THEN
    ALTER TABLE specs_knowledge_base RENAME COLUMN market_value TO "Market_Value";
  END IF;
END $$;

-- 2) تصنيف الإشعارات وربطها بطلبات الموافقة
ALTER TABLE admin_notifications ADD COLUMN IF NOT EXISTS notif_type VARCHAR(50);
ALTER TABLE admin_notifications ADD COLUMN IF NOT EXISTS related_id BIGINT;

-- 3) طلبات محتاجة موافقة أدمن (تعديل بارت نمبر/سريال، استيراد قاعدة معرفة)
CREATE TABLE IF NOT EXISTS pending_approvals (
    id BIGSERIAL PRIMARY KEY,
    approval_type VARCHAR(50) NOT NULL, -- 'part_number_edit' | 'serial_edit' | 'kb_import'
    payload JSONB NOT NULL,
    requested_by VARCHAR(50) REFERENCES users(username),
    status VARCHAR(20) DEFAULT 'Pending', -- Pending / Approved / Rejected
    created_at TIMESTAMP DEFAULT now(),
    resolved_by VARCHAR(50) REFERENCES users(username),
    resolved_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON pending_approvals(status);

-- 4) تشغيل/إيقاف كل نوع إشعار من الإعدادات
CREATE TABLE IF NOT EXISTS notification_settings (
    notif_type VARCHAR(50) PRIMARY KEY,
    enabled BOOLEAN DEFAULT TRUE
);
INSERT INTO notification_settings (notif_type, enabled) VALUES
    ('new_query', TRUE),
    ('part_number_edit', TRUE),
    ('serial_edit', TRUE),
    ('kb_import', TRUE)
ON CONFLICT (notif_type) DO NOTHING;

-- 5) تحكم فردي لكل حساب في ظهور أي تبويب (فوق افتراضي الدور)
CREATE TABLE IF NOT EXISTS user_tab_overrides (
    username VARCHAR(50) REFERENCES users(username),
    tab_id VARCHAR(50) NOT NULL,
    enabled BOOLEAN NOT NULL,
    updated_by VARCHAR(50) REFERENCES users(username),
    updated_at TIMESTAMP DEFAULT now(),
    PRIMARY KEY (username, tab_id)
);

-- 6) نسخة احتياطية من قاعدة المعرفة قبل كل استيراد جديد
CREATE TABLE IF NOT EXISTS kb_import_backups (
    id BIGSERIAL PRIMARY KEY,
    snapshot JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    created_by VARCHAR(50) REFERENCES users(username)
);

-- 7) مين أنشأ الحساب (created_by كان ناقص)
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_by VARCHAR(50);