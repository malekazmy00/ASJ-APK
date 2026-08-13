-- 016_state_transition_guards.sql
-- مراجعة شاملة لكل State Transition في المشروع (زي ما اتفقنا: مش
-- Dispatch/Return بس — أي عملية بتغيّر status/ownership/presence).
--
-- المشكلة اللي كانت موجودة في كل الدوال دي: بتعمل UPDATE من غير أي
-- شرط على الحالة الحالية للصف. لو جلستان نفذوا نفس العملية في نفس
-- اللحظة (Race Condition)، الاتنين كانوا بينجحوا بصمت — مثلاً قطعة
-- واحدة تتصرف مرتين، أو طلب موافقة يتحسم مرتين.
--
-- الإصلاح: أي UPDATE بيغيّر حالة، شرط الحالة القديمة بقى **جوه نفس
-- جملة الـ UPDATE نفسها** (WHERE status = ...) مش SELECT منفصل قبلها
-- — فمهما حصل تسابق، صف واحد بس هو اللي يعدّي الشرط وينجح فعلياً.
-- الجدول المطلوب:
--
--   العملية    الحالة الحالية   الحالة الجديدة   مسموح؟
--   Dispatch   Available/*      Out              لو مش Out أصلاً
--   Return     Out              Available         لو Out أصلاً
--   Archive    غير Archived     Archived          لو مش متأرشفة أصلاً
--   Approval   Pending          Approved/Rejected  لو لسه Pending
--
-- أي فشل في الشرط بيرمي استثناء مبدوء بـ 'BUSINESS_ERROR:' — الـ Edge
-- Function بتتعرف عليه وترجع 409 برسالة عربية واضحة، بدل 500 عام.
--
-- شغّلها يدوياً على Supabase SQL Editor. آمنة تتكرر.

-- ============================================================
-- 1) Dispatch — القطعة لازم متكونش Out أصلاً
-- ============================================================
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
  RETURNING * INTO v_item;

  IF NOT FOUND THEN
    -- ممكن السبب إن القطعة مش موجودة أصلاً، أو (الأرجح) إنها اتصرفت
    -- خلال آخر لحظات (تسابق من جلسة تانية) — رسالة واحدة تغطي الحالتين.
    RAISE EXCEPTION 'BUSINESS_ERROR: القطعة رقم % غير متاحة للصرف حالياً (ممكن اتصرفت للتو أو مش موجودة)', p_item_id;
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

-- ============================================================
-- 2) Return — القطعة لازم تكون Out فعلاً
-- ============================================================
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
  UPDATE inventory_items
  SET status = 'Available', updated_at = now()
  WHERE item_id = p_item_id
    AND status = 'Out'
  RETURNING * INTO v_item;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BUSINESS_ERROR: القطعة رقم % مش صادرة أصلاً (ممكن اتسجلت مرتجعة للتو أو مش موجودة)', p_item_id;
  END IF;

  INSERT INTO transactions_log (item_id, action_type, username, details)
  VALUES (p_item_id, 'RETURN', p_username, p_details);

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

-- ============================================================
-- 3) Archive — القطعة لازم متكونش متأرشفة أصلاً
-- ============================================================
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
    AND status <> 'Archived'
  RETURNING * INTO v_item;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BUSINESS_ERROR: القطعة رقم % متأرشفة بالفعل (أو مش موجودة)', p_item_id;
  END IF;

  INSERT INTO transactions_log (item_id, action_type, username, details)
  VALUES (p_item_id, 'DELETE', p_deleted_by, 'أرشفة — السبب: ' || p_reason);

  RETURN v_item;
END;
$$;

-- ============================================================
-- 4) تعديل بيانات أساسية — منع التعديل على قطعة متأرشفة (حماية
--    إضافية: القطعة المؤرشفة مش المفروض تتعدل بيانتها بعد الأرشفة)
-- ============================================================
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

-- ============================================================
-- 5) الموافقة على طلب معلّق — نفس فئة المشكلة بالظبط: كان بيتحقق
--    (SELECT ثم IF) قبل الـ UPDATE بدل ما يكون الشرط جوه UPDATE نفسها،
--    فطلبين موافقة/رفض في نفس اللحظة كانوا ممكن يعدّوا الاتنين.
--    الحل: "المطالبة" (claim) بالطلب تبقى UPDATE واحدة بشرط status='Pending'
--    — لو صف واحد بس رجع، إحنا واثقين إننا الوحيدين اللي بنعالج الطلب ده.
-- ============================================================
CREATE OR REPLACE FUNCTION claim_pending_approval_tx(
  p_approval_id INT,
  p_new_status TEXT,  -- 'Approved' أو 'Rejected'
  p_resolved_by TEXT
)
RETURNS pending_approvals
LANGUAGE plpgsql
AS $$
DECLARE
  v_approval pending_approvals;
BEGIN
  IF p_new_status NOT IN ('Approved', 'Rejected') THEN
    RAISE EXCEPTION 'BUSINESS_ERROR: قيمة status غير صالحة';
  END IF;

  UPDATE pending_approvals
  SET status = p_new_status,
      resolved_by = p_resolved_by,
      resolved_at = now()
  WHERE id = p_approval_id
    AND status = 'Pending'
  RETURNING * INTO v_approval;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'BUSINESS_ERROR: الطلب ده اتحسم قبل كده أو مش موجود';
  END IF;

  RETURN v_approval;
END;
$$;

REVOKE EXECUTE ON FUNCTION dispatch_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION return_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION archive_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION update_item_basic_fields_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION claim_pending_approval_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION dispatch_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION return_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION archive_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION update_item_basic_fields_tx TO service_role;
GRANT EXECUTE ON FUNCTION claim_pending_approval_tx TO service_role;
