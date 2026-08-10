-- 005_round3_min_version.sql
-- الجولة الثالثة — نقطة ٢٢: جدول عام لإعدادات التطبيق، بيتسجل فيه أقل
-- نسخة مسموح بيها (min_required_version). شغّله يدوياً على Supabase
-- SQL Editor. آمن يتكرر.

CREATE TABLE IF NOT EXISTS app_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- القيمة الافتراضية = نفس رقم النسخة الحالي في pubspec.yaml (0.1.0)،
-- عشان محدش يتوقف فجأة من غير ما تكون قصدت كده. لما تطلع نسخة جديدة
-- وعايز تجبر عليها، غيّر القيمة دي:
--   UPDATE app_config SET value = '0.2.0' WHERE key = 'min_required_version';
INSERT INTO app_config (key, value) VALUES ('min_required_version', '0.1.0')
ON CONFLICT (key) DO NOTHING;