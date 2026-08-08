-- 004_round3.sql
-- الجولة الثالثة — Batch A: تسجيل أنواع الإشعارات الموسّعة (نقطة ١١)
-- في notification_settings عشان تظهر افتراضياً في شاشة الإعدادات.
-- شغّله يدوياً على Supabase SQL Editor. آمن يتكرر.

INSERT INTO notification_settings (notif_type, enabled) VALUES
    ('part_entry', true),
    ('dispatch', true),
    ('return', true),
    ('part_number_edit', true),
    ('serial_edit', true),
    ('new_query', true),
    ('kb_import', true),
    ('kb_export', true),
    ('login', false),
    ('session_end', false),
    ('user_created', true),
    ('permissions_changed', true),
    ('admin_password_reset', true),
    ('self_password_change', false),
    ('approval_created', true),
    ('approval_resolved', true)
ON CONFLICT (notif_type) DO NOTHING;