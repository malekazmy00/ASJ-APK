-- 014_update_fields_atomic.sql
-- آخر نقطة من الفجوات الموثّقة في SECURITY.md: تعديل البيانات الأساسية
-- (موقع/حالة فنية/حالة ملكية/حالة القطعة/سريال غير الحساس/ملاحظات)
-- كان بيتم بنداء update() مباشر على الجدول بمفتاح anon، من غير أي
-- تحقق دور سيرفر-سايد ومن غير أي سجل atomic مضمون مع الـ log.
--
-- الدالة دي بتعمل التحديث + سجل الحركة مع بعض، وممنوعة تتنادى مباشرة
-- من anon (لازم تعدّي على Edge Function `update-item-fields`، اللي
-- كمان بتتحقق من صلاحية can_edit فعلياً — مش بس تعرض/تخفي الزرار في
-- الواجهة زي ما كان يحصل قبل كده).
--
-- ملحوظة: تعديل رقم القطعة والسريال (الحقول الحساسة) لسه مسارهم
-- الأصلي عن طريق نظام الموافقة (pending_approvals + resolve-approval)
-- زي ما هو بالظبط — الدالة دي بتغطي بس الحقول العادية اللي كانت بتتطبق
-- فوراً من غير موافقة.
--
-- شغّلها يدوياً على Supabase SQL Editor. آمنة تتكرر.

CREATE OR REPLACE FUNCTION update_item_basic_fields_tx(
  p_item_id INT,
  p_username TEXT,
  p_location TEXT,
  p_condition TEXT,
  p_ownership_status TEXT,
  p_status TEXT DEFAULT NULL,
  p_update_status BOOLEAN DEFAULT false,
  p_notes TEXT DEFAULT NULL,
  p_update_notes BOOLEAN DEFAULT false,
  p_serial_number TEXT DEFAULT NULL,
  p_update_serial BOOLEAN DEFAULT false,
  p_log_details TEXT DEFAULT 'تعديل بيانات أساسية'
)
RETURNS inventory_items
LANGUAGE plpgsql
AS $$
DECLARE
  v_item inventory_items;
BEGIN
  UPDATE inventory_items SET
    location = p_location,
    condition = p_condition,
    ownership_status = p_ownership_status,
    status = CASE WHEN p_update_status THEN p_status ELSE status END,
    notes = CASE WHEN p_update_notes THEN p_notes ELSE notes END,
    serial_number = CASE WHEN p_update_serial THEN p_serial_number ELSE serial_number END,
    updated_at = now()
  WHERE item_id = p_item_id
  RETURNING * INTO v_item;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'القطعة رقم % غير موجودة', p_item_id;
  END IF;

  INSERT INTO transactions_log (item_id, action_type, username, details)
  VALUES (p_item_id, 'UPDATE', p_username, p_log_details);

  RETURN v_item;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_item_basic_fields_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION update_item_basic_fields_tx TO service_role;
