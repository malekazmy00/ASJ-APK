-- 015_archive_atomic.sql
-- آخر نقطة من مصفوفة SECURITY.md: الأرشفة (بديل الحذف النهائي، TASK-306)
-- كانت update() مباشر على الجدول بمفتاح anon، من غير تحقق دور
-- سيرفر-سايد ومن غير سجل حركة atomic مضمون مع التحديث.
--
-- نفس نمط update-item-fields بالظبط: RPC ذرية (تحديث + سجل حركة) +
-- Edge Function بتتحقق من التوكن وصلاحية can_edit فعلياً، وممنوعة
-- تتنادى مباشرة من anon.
--
-- شغّلها يدوياً على Supabase SQL Editor. آمنة تتكرر.

CREATE OR REPLACE FUNCTION archive_item_tx(
  p_item_id INT,
  p_deleted_by TEXT,
  p_reason TEXT
)
RETURNS inventory_items
LANGUAGE plpgsql
AS $$
DECLARE
  v_item inventory_items;
BEGIN
  UPDATE inventory_items SET
    status = 'Archived',
    deleted_at = now(),
    deleted_by = p_deleted_by,
    delete_reason = p_reason,
    updated_at = now()
  WHERE item_id = p_item_id
  RETURNING * INTO v_item;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'القطعة رقم % غير موجودة', p_item_id;
  END IF;

  -- 'DELETE' هو نفس dbValue بتاع ActionType.delete المستخدم أصلاً في
  -- التطبيق لعمليات الأرشفة (راجع engineer_home_screen.dart) — مش
  -- قيمة جديدة، عشان ActionType.fromDb() يعرف يترجمها صح في أي شاشة
  -- سجل/تتبع بدل ما ترجع "بحث" (fallback الافتراضي لقيمة مش معروفة).
  INSERT INTO transactions_log (item_id, action_type, username, details)
  VALUES (p_item_id, 'DELETE', p_deleted_by, 'أرشفة — السبب: ' || p_reason);

  RETURN v_item;
END;
$$;

REVOKE EXECUTE ON FUNCTION archive_item_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION archive_item_tx TO service_role;
