-- 009_session_expiry_and_revocation.sql
-- TASK-310: "detached" مش ضمانة لإغلاق الجلسة — Android ممكن يقتل
-- العملية من غير أي فرصة للتطبيق ينفّذ stop(). الدالة دي بتقفل أي
-- جلسة last_activity_at بتاعها أقدم من 30 دقيقة ومفيهاش logout_at
-- أصلاً (يعني ظاهرة "لسه شغالة" غلط)، وبتتنادى best-effort من التطبيق
-- (بعد فتح أي سيشن جديدة، وقبل عرض تقارير النشاط).
--
-- TASK-309: تغيير كلمة المرور (سواء المستخدم نفسه أو الأدمن) بيقفل
-- كل الجلسات المفتوحة لنفس الحساب، وكمان بيلغي صلاحية أي توكن (JWT)
-- قديم كان اتولّد قبل التغيير — راجع password_changed_at وrequireAuth
-- في supabase/functions/_shared/auth.ts.
--
-- شغّلهم يدوياً على Supabase SQL Editor. آمنين يتكرروا (CREATE OR REPLACE).

ALTER TABLE users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION close_stale_sessions()
RETURNS void
LANGUAGE sql
AS $$
  UPDATE user_sessions
  SET logout_at = last_activity_at
  WHERE logout_at IS NULL
    AND last_activity_at < now() - interval '30 minutes';
$$;

GRANT EXECUTE ON FUNCTION close_stale_sessions TO anon, authenticated;

CREATE OR REPLACE FUNCTION revoke_all_sessions(p_username TEXT)
RETURNS void
LANGUAGE sql
AS $$
  UPDATE user_sessions
  SET logout_at = now()
  WHERE username = p_username
    AND logout_at IS NULL;
$$;

-- ملحوظة (بعد TASK-401): الدالة دي بتتنادى بس من جوه change-password
-- وadmin-reset-password (Edge Functions بتستخدم service_role client
-- أصلاً) — مفيش سبب شرعي إنها تتنادى مباشرة من anon بمفتاح anon، وده
-- كان بيسمح لأي حد يجبر تسجيل خروج أي مستخدم تاني بمجرد معرفة اسمه.
GRANT EXECUTE ON FUNCTION revoke_all_sessions TO service_role;
