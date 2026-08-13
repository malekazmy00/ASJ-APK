-- 008_atomic_inventory_insert.sql
-- TASK-304 + TASK-305: عملية "تسجيل قطعة" (worker entry) بقت transaction
-- واحدة ذرية على مستوى قاعدة البيانات — إدراج القطعة + تحديث قاعدة
-- المعرفة + تسجيل الـ audit + الإشعار، كلهم مع بعض أو ولا حاجة.
--
-- قبل كده كل خطوة كانت نداء منفصل من Flutter (bulkInsert ثم
-- createOrAppendInsight ثم setPartModelIfEmpty ثم logAction ثم
-- notifRepo.create) — لو خطوة نصف الطريق فشلت (مثلاً الشبكة قطعت بعد
-- إدراج القطعة وقبل تسجيل الـ audit)، القطعة كانت تتسجل في المخزون
-- من غير أي سجل حركة ليها، وهو وضع غير مقبول في نظام مخازن.
--
-- الدالة دي بتتنفذ كوحدة واحدة في Postgres (أي exception جواها بترجّع
-- كل حاجة تمت جواها تلقائياً — مفيش حاجة نصها بتتسجل).
--
-- شغّلها يدوياً على Supabase SQL Editor. آمن تتكرر (CREATE OR REPLACE).

CREATE OR REPLACE FUNCTION create_inventory_item_tx(
  p_item_type TEXT,
  p_part_number TEXT,
  p_description TEXT,
  p_notes TEXT,
  p_entry_type TEXT,
  p_location TEXT,
  p_condition TEXT,
  p_serial_number TEXT,
  p_ownership_status TEXT,
  p_username TEXT,
  p_gemini_insights TEXT DEFAULT NULL,
  p_part_model TEXT DEFAULT NULL,
  p_log_details TEXT DEFAULT '',
  p_notif_message TEXT DEFAULT NULL
)
RETURNS inventory_items
LANGUAGE plpgsql
AS $$
DECLARE
  v_item inventory_items;
  v_has_part_number BOOLEAN := p_part_number IS NOT NULL AND p_part_number <> '' AND p_part_number <> 'PENDING';
  v_existing_insights TEXT;
  v_existing_part_model TEXT;
  v_notif_enabled BOOLEAN;
BEGIN
  -- 1) إدراج القطعة نفسها
  INSERT INTO inventory_items (
    item_type, part_number, description, notes, entry_type, location,
    condition, serial_number, status, ownership_status
  ) VALUES (
    p_item_type, p_part_number, p_description, p_notes, p_entry_type, p_location,
    p_condition, p_serial_number, 'Available', p_ownership_status
  )
  RETURNING * INTO v_item;

  -- 2) قاعدة المعرفة — نفس منطق KnowledgeBaseRepository.createOrAppendInsight
  -- وsetPartModelIfEmpty بالظبط، بس دلوقتي جوه نفس الـ transaction.
  IF v_has_part_number THEN
    SELECT "Gemini_Insights", "Part_Model"
      INTO v_existing_insights, v_existing_part_model
      FROM specs_knowledge_base
      WHERE "Part_Number" = p_part_number;

    IF NOT FOUND THEN
      INSERT INTO specs_knowledge_base ("Part_Number", "Gemini_Insights", "Part_Model")
      VALUES (p_part_number, NULLIF(p_gemini_insights, ''), NULLIF(p_part_model, ''));
    ELSE
      IF p_gemini_insights IS NOT NULL AND p_gemini_insights <> ''
         AND (v_existing_insights IS NULL OR position(p_gemini_insights IN v_existing_insights) = 0) THEN
        UPDATE specs_knowledge_base
        SET "Gemini_Insights" = CASE
              WHEN v_existing_insights IS NULL OR v_existing_insights = '' THEN p_gemini_insights
              ELSE v_existing_insights || E'\n---\n' || p_gemini_insights
            END,
            last_updated = now()
        WHERE "Part_Number" = p_part_number;
      END IF;

      IF p_part_model IS NOT NULL AND p_part_model <> ''
         AND (v_existing_part_model IS NULL OR v_existing_part_model = '') THEN
        UPDATE specs_knowledge_base
        SET "Part_Model" = p_part_model, last_updated = now()
        WHERE "Part_Number" = p_part_number;
      END IF;
    END IF;
  END IF;

  -- 3) الـ Audit — نفس الـ transaction بالظبط، فمفيش احتمال قطعة
  -- تتسجل من غير سجل حركة ليها (كان ده أخطر جزء في TASK-305).
  INSERT INTO transactions_log (item_id, action_type, username, details)
  VALUES (v_item.item_id, 'INSERT', p_username, p_log_details);

  -- 4) الإشعار (بيتفحص notification_settings زي أي إشعار تاني). دعم
  -- {item_id} كـ placeholder جوه الرسالة — رقم القطعة مش معروف إلا
  -- بعد الإدراج، فمينفعش يتحط في الرسالة من الـ Flutter قبل النداء.
  IF p_notif_message IS NOT NULL THEN
    SELECT enabled INTO v_notif_enabled
      FROM notification_settings WHERE notif_type = 'part_entry';
    IF v_notif_enabled IS NULL OR v_notif_enabled = true THEN
      INSERT INTO admin_notifications (message, notif_type, related_id)
      VALUES (
        replace(p_notif_message, '{item_id}', v_item.item_id::text),
        'part_entry',
        v_item.item_id
      );
    END IF;
  END IF;

  RETURN v_item;
END;
$$;

-- التطبيق بينادي الدالة دي بمفتاح anon (نفس نموذج الثقة الحالي — RLS
-- متعطلة عمداً، التحقق على مستوى التطبيق مش الداتابيز، راجع
-- auth_service.dart). لازم صلاحية التنفيذ للـ role دي صراحةً.
GRANT EXECUTE ON FUNCTION create_inventory_item_tx TO anon, authenticated;
