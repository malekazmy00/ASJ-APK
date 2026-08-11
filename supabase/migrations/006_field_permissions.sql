-- 006_field_permissions.sql
-- نظام التحكم في ظهور العناصر الداخلية جوه ٥ تبويبات (تسجيل قطعة،
-- المخزون، لوحة التعديل، التصدير، تحليل البيانات)، لكل حساب لوحده.
-- شغّله يدوياً على Supabase SQL Editor. آمن يتكرر.

CREATE TABLE IF NOT EXISTS user_field_overrides (
    username TEXT NOT NULL,
    tab_id TEXT NOT NULL,
    field_key TEXT NOT NULL,
    visible BOOLEAN NOT NULL,
    updated_by TEXT,
    updated_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (username, tab_id, field_key)
);