-- 007_soft_delete.sql
-- TASK-306: إلغاء الحذف النهائي (DELETE) من الاستخدام التشغيلي العادي
-- في التطبيق، والاستعاضة عنه بأرشفة قابلة للتراجع (soft delete) —
-- عشان محافظين على التاريخ/الـ audit/الـ traceability. شغّله يدوياً
-- على Supabase SQL Editor. آمن يتكرر.

ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS deleted_by TEXT;
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS delete_reason TEXT;
