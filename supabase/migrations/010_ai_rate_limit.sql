-- 010_ai_rate_limit.sql
-- TASK-319: جدول تتبع نداءات AI endpoints (analyze-part, search-part)
-- لكل مستخدم — عشان نقدر نحدد معدل الاستخدام (راجع
-- supabase/functions/_shared/rate_limit.ts). قبل كده الدالتين دول
-- كانوا مفتوحين تماماً من غير أي تحقق هوية، فمفيش وسيلة أصلاً كانت
-- تعرف مين استهلك الحصة.
--
-- شغّله يدوياً على Supabase SQL Editor. آمن يتكرر.

CREATE TABLE IF NOT EXISTS ai_request_log (
    id BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    endpoint TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_request_log_lookup
    ON ai_request_log (username, endpoint, created_at);
