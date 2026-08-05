-- 001_pending_and_new_tables.sql
-- شغّلها يدوياً في SQL Editor على Supabase (نفس أسلوب العمل المتبع سابقاً).

-- 1) عمود serial_number المعلّق من قبل (النظام الأصلي)
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS serial_number VARCHAR(100);

-- 2) جدول جلسات المستخدمين (تتبع جلسات الدخول - المرحلة 3)
CREATE TABLE IF NOT EXISTS user_sessions (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL REFERENCES users(username),
    login_at TIMESTAMP NOT NULL DEFAULT now(),
    last_activity_at TIMESTAMP NOT NULL DEFAULT now(),
    logout_at TIMESTAMP,
    device_info VARCHAR(255)
);
CREATE INDEX IF NOT EXISTS idx_sessions_username ON user_sessions(username);
CREATE INDEX IF NOT EXISTS idx_sessions_login_at ON user_sessions(login_at);

-- 3) View التجميع للداشبورد التجميعي (المرحلة 3)
CREATE OR REPLACE VIEW inventory_items_grouped AS
SELECT
    part_number,
    item_type,
    COUNT(*) AS qty,
    COUNT(*) FILTER (WHERE status = 'Available') AS qty_available,
    MAX(created_at) AS last_added_at
FROM inventory_items
GROUP BY part_number, item_type
ORDER BY qty DESC;

-- 4) فهرس لتسريع البحث النصي (ILIKE) المستخدم في smartSearch/searchByCategoryOrPart
-- بدون الفهرس ده، ILIKE بيعمل Sequential Scan كامل على الجدول كل بحث،
-- وهيبقى بطيء تدريجياً مع زيادة عدد القطع. آمن التنفيذ على جدول شغال.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_inventory_part_trgm
    ON inventory_items USING gin (part_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_kb_part_trgm
    ON specs_knowledge_base USING gin ("Part_Number" gin_trgm_ops);
