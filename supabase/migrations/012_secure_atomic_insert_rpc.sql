-- 012_secure_atomic_insert_rpc.sql
-- TASK-401: create_inventory_item_tx (008) كانت متاحة تُستدعى مباشرة
-- من Flutter عبر PostgREST (.rpc()) بمفتاح anon — ده مسار منفصل
-- تماماً عن طبقة الـ Authorization اللي بنيناها في Edge Functions
-- (_shared/auth.ts). يعني أي حد معاه مفتاح anon (موجود جوه أي نسخة
-- APK مثبتة) كان يقدر ينادي الدالة مباشرة ويحط أي p_username يحبه،
-- من غير أي تحقق هوية حقيقي — بالظبط نفس نوع الثغرة اللي قفلناها في
-- TASK-301/303 لكن من باب تاني (RPC مباشر بدل REST مباشر).
--
-- الحل: نمنع anon/authenticated من نداء الدالة مباشرة، وتبقى الدالة
-- قابلة للتنفيذ من service_role بس — يعني لازم تتنادى من Edge Function
-- (create-inventory-item) اللي بتتحقق من التوكن الأول (راجع
-- supabase/functions/create-inventory-item/index.ts).
--
-- شغّلها يدوياً على Supabase SQL Editor. آمنة تتكرر.

REVOKE EXECUTE ON FUNCTION create_inventory_item_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION create_inventory_item_tx TO service_role;
