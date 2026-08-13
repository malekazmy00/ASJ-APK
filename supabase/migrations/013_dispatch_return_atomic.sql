-- 013_dispatch_return_atomic.sql
-- التالي بعد TASK-401 (زي ما اتفقنا: صرف/استرجاع لازم تبقى atomic
-- ومحمية سيرفر-سايد زي تسجيل القطعة بالظبط).
--
-- قبل كده كل من الصرف والاسترجاع كانوا 2-3 نداءات منفصلة من Flutter
-- (logAction ثم updateStatus ثم notification)، بمفتاح anon مباشرة على
-- الجداول — نفس فئة مشكلة TASK-401 (مفيش تحقق هوية سيرفر-سايد)، وفي
-- نفس الوقت مش atomic (لو فشلت خطوة نص الطريق، القطعة ممكن تتغير
-- حالتها من غير سجل حركة أو العكس).
--
-- الدالتين دول بيعملوا الحركة + تغيير الحالة + الإشعار في transaction
-- واحدة، وممنوعين يتناديوا مباشرة من anon (لازم يعدّوا على
-- Edge Functions dispatch-item/return-item — راجع
-- supabase/functions/dispatch-item و return-item).
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
  INSERT INTO transactions_log (item_id, action_type, username, details, exit_type)
  VALUES (p_item_id, 'OUT', p_username, p_details, p_exit_type);

  UPDATE inventory_items
  SET status = 'Out', updated_at = now()
  WHERE item_id = p_item_id
  RETURNING * INTO v_item;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'القطعة رقم % غير موجودة', p_item_id;
  END IF;

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

CREATE OR REPLACE FUNCTION return_item_tx(
  p_item_id INT,
  p_username TEXT,
  p_details TEXT,
  p_notif_message TEXT DEFAULT NULL
)
RETURNS inventory_items
LANGUAGE plpgsql
AS $$
DECLARE
  v_item inventory_items;
  v_notif_enabled BOOLEAN;
BEGIN
  INSERT INTO transactions_log (item_id, action_type, username, details)
  VALUES (p_item_id, 'RETURN', p_username, p_details);

  UPDATE inventory_items
  SET status = 'Available', updated_at = now()
  WHERE item_id = p_item_id
  RETURNING * INTO v_item;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'القطعة رقم % غير موجودة', p_item_id;
  END IF;

  IF p_notif_message IS NOT NULL THEN
    SELECT enabled INTO v_notif_enabled
      FROM notification_settings WHERE notif_type = 'return';
    IF v_notif_enabled IS NULL OR v_notif_enabled = true THEN
      INSERT INTO admin_notifications (message, notif_type, related_id)
      VALUES (p_notif_message, 'return', p_item_id);
    END IF;
  END IF;

  RETURN v_item;
END;
$$;

REVOKE EXECUTE ON FUNCTION dispatch_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION return_item_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION dispatch_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION return_item_tx TO service_role;
