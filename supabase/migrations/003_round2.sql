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