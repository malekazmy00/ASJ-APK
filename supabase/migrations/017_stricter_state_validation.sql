-- 017_stricter_state_validation.sql
-- تكملة لـ 016: مراجعة إضافية لقت نقطتين إضافيتين حقيقيتين:
--
-- 1) update_item_basic_fields_tx كانت بتقبل أي نص كـ p_status (لو
--    update_status=true) من غير أي تحقق إنه فعلاً واحد من الحالات
--    المعروفة (Available/Out/Reserved/Damaged) — القيم الأربعة دي هي
--    بالظبط خيارات الدروب-داون الموجودة في الواجهة، فمفيش أي تغيير في
--    السلوك الحالي، بس رفض لأي قيمة غريبة لو حد استدعى الدالة مباشرة.
--
-- 2) dispatch_item_tx كان بيمنع بس "القطعة صادرة أصلاً" — بس مكنش
--    بيمنع صرف قطعة متأرشفة (لو حد قدر يستدعيها بـ item_id بتاع قطعة
--    متأرشفة، حتى لو الواجهة نفسها ما بتعرضش القطع المؤرشفة أصلاً في
--    أي شاشة اختيار). إضافة دفاعية بحتة.
--
-- شغّلها يدوياً على Supabase SQL Editor. آمنة تتكرر.

CREATE OR REPLACE FUNCTION dispatch_item_tx(
  p_item_id INT,
  p_username TEXT,
  p_details TEXT,
  p_exit_type TEXT,
  p_notif_message TEXT DEFAULT NULL
)
RETURNS inventory_items
LANGUAGE plpgsql
AS $$
DECLARE
  v_item inventory_items;
  v_notif_enabled BOOLEAN;
BEGIN
  UPDATE inventory_items
  SET status = 'Out', updated_at = now()
  WHERE item_id = p_item_id
    AND status <> 'Out'
    AND status <> 'Archived'
  RETURNING * INTO v_item;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BUSINESS_ERROR: القطعة رقم % غير متاحة للصرف حالياً (ممكن اتصرفت للتو أو متأرشفة أو مش موجودة)', p_item_id;
  END IF;

  INSERT INTO transactions_log (item_id, action_type, username, details, exit_type)
  VALUES (p_item_id, 'OUT', p_username, p_details, p_exit_type);

  IF p_notif_message IS NOT NULL THEN
    SELECT enabled INTO v_notif_enabled
      FROM notification_settings WHERE notif_type = 'dispatch';
    IF v_notif_enabled IS NULL OR v_notif_enabled = true THEN
      INSERT INTO admin_notifications (message, notif_type, related_id)
      VALUES (p_notif_message, 'dispatch', p_item_id);
    END IF;
  END IF;

  RETURN v_item;
END;
$$;

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
  -- نفس القيم الأربعة بالظبط اللي في enum ItemStatus (lib/core/models/
  -- enums.dart) واللي الدروب-داون في الواجهة بيعرضها — مفيش أي قيمة
  -- شرعية حالية بتتمنع، بس أي نص عشوائي هيترفض.
  IF p_update_status AND p_status NOT IN ('Available', 'Out', 'Reserved', 'Damaged') THEN
    RAISE EXCEPTION 'BUSINESS_ERROR: حالة قطعة غير معروفة';
  END IF;

  UPDATE inventory_items SET
    location = p_location,
    condition = p_condition,
    ownership_status = p_ownership_status,
    status = CASE WHEN p_update_status THEN p_status ELSE status END,
    notes = CASE WHEN p_update_notes THEN p_notes ELSE notes END,
    serial_number = CASE WHEN p_update_serial THEN p_serial_number ELSE serial_number END,
    updated_at = now()
  WHERE item_id = p_item_id
    AND status <> 'Archived'
  RETURNING * INTO v_item;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BUSINESS_ERROR: القطعة رقم % متأرشفة أو مش موجودة — مينفعش تتعدل', p_item_id;
  END IF;

  INSERT INTO transactions_log (item_id, action_type, username, details)
  VALUES (p_item_id, 'UPDATE', p_username, p_log_details);

  RETURN v_item;
END;
$$;

REVOKE EXECUTE ON FUNCTION dispatch_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION update_item_basic_fields_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION dispatch_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION update_item_basic_fields_tx TO service_role;
