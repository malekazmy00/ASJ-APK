-- schema_test_db.sql
--
-- سكريبت واحد كامل لإنشاء قاعدة بيانات اختبار مطابقة تماماً لبنية
-- الإنتاج، من الصفر، في مشروع Supabase منفصل تماماً (فاضي جديد).
--
-- الاستخدام: اعمل مشروع Supabase جديد مخصص للتجربة فقط (فري تير كافي)،
-- افتح SQL Editor فيه، الصق السكريبت ده كامل وشغّله مرة واحدة.
-- ملحوظة: ده لقاعدة اختبار فاضية جديدة بس — لا تشغّله أبداً على قاعدة
-- البيانات الحقيقية اللي عليها بيانات فعلية.

-- ===========================================================
-- 1) الجداول الأساسية (مطابقة لـ core/models.py في النظام الأصلي)
-- ===========================================================

CREATE TABLE IF NOT EXISTS users (
    username VARCHAR(50) PRIMARY KEY,
    password VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'worker',
    can_export BOOLEAN DEFAULT FALSE,
    can_track BOOLEAN DEFAULT FALSE,
    can_edit BOOLEAN DEFAULT FALSE,
    status VARCHAR(20) DEFAULT 'Active',
    created_at TIMESTAMP DEFAULT now(),
    last_login TIMESTAMP,
    last_ip VARCHAR(45),
    last_user_agent VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS inventory_items (
    item_id SERIAL PRIMARY KEY,
    item_type VARCHAR(100) DEFAULT 'بوردة',
    part_number VARCHAR(100) DEFAULT 'PENDING',
    location VARCHAR(100),
    condition VARCHAR(50),
    image_path VARCHAR(500),
    ocr_text TEXT,
    status VARCHAR(20) DEFAULT 'Available',
    sync_status VARCHAR(20) DEFAULT 'Offline_Queue',
    serial_number VARCHAR(100),
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inventory_status ON inventory_items(status);
CREATE INDEX IF NOT EXISTS idx_inventory_part ON inventory_items(part_number);
CREATE INDEX IF NOT EXISTS idx_inventory_item_type ON inventory_items(item_type);

CREATE TABLE IF NOT EXISTS specs_knowledge_base (
    "Part_Number" VARCHAR(100) PRIMARY KEY,
    "Brand" TEXT,
    "Category" TEXT,
    "Compatible_Model" TEXT,
    "Additional_Compatibility" TEXT,
    market_value TEXT,
    "Gemini_Insights" TEXT,
    last_updated TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transactions_log (
    log_id SERIAL PRIMARY KEY,
    item_id INTEGER,
    action_type VARCHAR(50) NOT NULL,
    username VARCHAR(50),
    details TEXT,
    ip_address VARCHAR(45) DEFAULT '0.0.0.0',
    user_agent VARCHAR(255),
    timestamp TIMESTAMP DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON transactions_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_username ON transactions_log(username);
CREATE INDEX IF NOT EXISTS idx_logs_action ON transactions_log(action_type);

CREATE TABLE IF NOT EXISTS engineer_queries (
    query_id SERIAL PRIMARY KEY,
    username VARCHAR(50),
    part_number VARCHAR(100),
    part_category VARCHAR(100),
    part_description TEXT,
    query_reason VARCHAR(100),
    requested_by VARCHAR(100),
    target_device VARCHAR(255),
    merchant_name VARCHAR(100),
    merchant_phone VARCHAR(50),
    comments TEXT,
    status VARCHAR(20) DEFAULT 'Pending',
    timestamp TIMESTAMP DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_queries_part ON engineer_queries(part_number);
CREATE INDEX IF NOT EXISTS idx_queries_status ON engineer_queries(status);
CREATE INDEX IF NOT EXISTS idx_queries_timestamp ON engineer_queries(timestamp);

CREATE TABLE IF NOT EXISTS admin_notifications (
    notif_id SERIAL PRIMARY KEY,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    timestamp TIMESTAMP DEFAULT now()
);

-- ===========================================================
-- 2) إضافات المرحلة 3 (نفس محتوى migrations/001 بالضبط)
-- ===========================================================

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

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_inventory_part_trgm
    ON inventory_items USING gin (part_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_kb_part_trgm
    ON specs_knowledge_base USING gin ("Part_Number" gin_trgm_ops);

-- ===========================================================
-- 3) بيانات تجريبية اختيارية (احذفها/عدّلها زي ما تحب)
-- ===========================================================
-- ملحوظة: عمود password هنا فاضي عمداً - أول مستخدم لازم يتعمل عن طريق
-- دالة admin-create-user (بعد نشرها) عشان الباسورد يتشفر صح بـ Argon2.
-- راجع الخطوة "تجهيز أول مستخدم اختبار" في الرد.
