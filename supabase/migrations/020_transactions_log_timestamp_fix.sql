-- 020_transactions_log_timestamp_fix.sql
--
-- عطل خامس من نفس النمط بالظبط (عمود timestamp بلا DEFAULT ومن غير أي
-- مسار إدراج بيحدده صراحة) — هنا على transactions_log نفسه، أهم جدول
-- audit في المشروع.
--
-- الأثر الفعلي المرصود وقت الفحص (راجع التقرير المرفق قبل الملف ده):
--   إجمالي 1005 صف، منهم 662 صف (65.9%) timestamp بتاعتهم NULL —
--   موزّعين على 4 أنواع أحداث مختلفة (INSERT/LOGIN/UPDATE/SEARCH)،
--   مش بس INSERT زي ما كان مفترض في البلاغ الأول.
--
-- ملحوظة مهمة عن أسلوب الـ Backfill (خروج مقصود عن حرفية الطلب،
-- موضّح في الرسالة المرفقة): item_id مش محور صالح للترتيب هنا لأن
-- جزء كبير من الصفوف (كل صفوف LOGIN مثلاً) item_id بتاعها NULL أصلاً
-- (مش عن عطل — دي طبيعة الحدث، تسجيل دخول مالوش قطعة مرتبطة بيه).
-- المحور المستخدم بدل كده هو log_id (المفتاح الأساسي للجدول نفسه،
-- BIGSERIAL، موجود لكل صف بلا استثناء) — نفس فلسفة الـ backfill في
-- migration 018 (notif_id) بالظبط، مطبّقة هنا على مفتاح الجدول
-- المناسب.
--
-- شغّلها يدوياً على Supabase SQL Editor — آمنة تتكرر بالكامل
-- (idempotent) زي 018/019 بالظبط.

-- ============================================================
-- 1) DEFAULT now()
-- ============================================================
ALTER TABLE transactions_log ALTER COLUMN "timestamp" SET DEFAULT now();

-- ============================================================
-- 2) كل الدوال (RPCs) اللي بتكتب في transactions_log — تحديد
--    "timestamp" = now() صراحة في كل INSERT (defense-in-depth فوق
--    الـ DEFAULT، نفس نمط 018/019 بالظبط)
-- ============================================================

-- 2.أ) create_inventory_item_tx
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
  INSERT INTO inventory_items (
    item_type, part_number, description, notes, entry_type, location,
    condition, serial_number, status, ownership_status, created_at
  ) VALUES (
    p_item_type, p_part_number, p_description, p_notes, p_entry_type, p_location,
    p_condition, p_serial_number, 'Available', p_ownership_status, now()
  )
  RETURNING * INTO v_item;

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

  -- timestamp صريحة (020) — مش هتتوقف على DEFAULT العمود بس.
  INSERT INTO transactions_log (item_id, action_type, username, details, "timestamp")
  VALUES (v_item.item_id, 'INSERT', p_username, p_log_details, now());

  IF p_notif_message IS NOT NULL THEN
    SELECT enabled INTO v_notif_enabled
      FROM notification_settings WHERE notif_type = 'part_entry';
    IF v_notif_enabled IS NULL OR v_notif_enabled = true THEN
      INSERT INTO admin_notifications (message, notif_type, related_id, "timestamp")
      VALUES (
        replace(p_notif_message, '{item_id}', v_item.item_id::text),
        'part_entry',
        v_item.item_id,
        now()
      );
    END IF;
  END IF;

  RETURN v_item;
END;
$$;

-- 2.ب) dispatch_item_tx
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

  INSERT INTO transactions_log (item_id, action_type, username, details, exit_type, "timestamp")
  VALUES (p_item_id, 'OUT', p_username, p_details, p_exit_type, now());

  IF p_notif_message IS NOT NULL THEN
    SELECT enabled INTO v_notif_enabled
      FROM notification_settings WHERE notif_type = 'dispatch';
    IF v_notif_enabled IS NULL OR v_notif_enabled = true THEN
      INSERT INTO admin_notifications (message, notif_type, related_id, "timestamp")
      VALUES (p_notif_message, 'dispatch', p_item_id, now());
    END IF;
  END IF;

  RETURN v_item;
END;
$$;

-- 2.ج) return_item_tx
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

  INSERT INTO transactions_log (item_id, action_type, username, details, "timestamp")
  VALUES (p_item_id, 'RETURN', p_username, p_details, now());

  IF p_notif_message IS NOT NULL THEN
    SELECT enabled INTO v_notif_enabled
      FROM notification_settings WHERE notif_type = 'return';
    IF v_notif_enabled IS NULL OR v_notif_enabled = true THEN
      INSERT INTO admin_notifications (message, notif_type, related_id, "timestamp")
      VALUES (p_notif_message, 'return', p_item_id, now());
    END IF;
  END IF;

  RETURN v_item;
END;
$$;

-- 2.د) update_item_basic_fields_tx
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
  v_notif_enabled BOOLEAN;
BEGIN
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

  INSERT INTO transactions_log (item_id, action_type, username, details, "timestamp")
  VALUES (p_item_id, 'UPDATE', p_username, p_log_details, now());

  SELECT enabled INTO v_notif_enabled
    FROM notification_settings WHERE notif_type = 'field_update';
  IF v_notif_enabled IS NULL OR v_notif_enabled = true THEN
    INSERT INTO admin_notifications (message, notif_type, related_id, "timestamp")
    VALUES (
      p_username || ' عدّل بيانات القطعة رقم ' || p_item_id,
      'field_update',
      p_item_id,
      now()
    );
  END IF;

  RETURN v_item;
END;
$$;

-- 2.هـ) archive_item_tx
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

  INSERT INTO transactions_log (item_id, action_type, username, details, "timestamp")
  VALUES (p_item_id, 'DELETE', p_deleted_by, 'أرشفة — السبب: ' || p_reason, now());

  RETURN v_item;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_inventory_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION dispatch_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION return_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION update_item_basic_fields_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION archive_item_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION create_inventory_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION dispatch_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION return_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION update_item_basic_fields_tx TO service_role;
GRANT EXECUTE ON FUNCTION archive_item_tx TO service_role;

-- ============================================================
-- 3) Backfill لكل صف timestamp IS NULL (662 صف وقت الفحص)
-- ============================================================
-- نفس تقنية الـ window functions المستخدمة في 018 بالظبط، بس المحور
-- هنا log_id (مفتاح الجدول نفسه) مش item_id — لأن item_id مش موجود
-- لكل الصفوف (LOGIN/EXPORT/USER_MGMT كتير منها item_id = NULL أصلاً،
-- ده طبيعي مش عطل). log_id بيحافظ على تسلسل زمني صحيح لكل الصفوف بلا
-- استثناء لأنه BIGSERIAL بيتزايد مع كل إدراج.
WITH gaps AS (
  SELECT
    log_id,
    "timestamp",
    MAX("timestamp") OVER (ORDER BY log_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS prev_ts,
    MIN("timestamp") OVER (ORDER BY log_id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS next_ts
  FROM transactions_log
),
grouped AS (
  SELECT
    log_id, prev_ts, next_ts,
    ROW_NUMBER() OVER (PARTITION BY prev_ts, next_ts ORDER BY log_id) AS rn,
    COUNT(*) OVER (PARTITION BY prev_ts, next_ts) AS cnt
  FROM gaps
  WHERE "timestamp" IS NULL
)
UPDATE transactions_log t
SET "timestamp" = CASE
  WHEN g.prev_ts IS NOT NULL AND g.next_ts IS NOT NULL THEN
    g.prev_ts + ((g.next_ts - g.prev_ts) * (g.rn::float8 / (g.cnt + 1)))
  WHEN g.prev_ts IS NOT NULL THEN
    g.prev_ts + ((now() - g.prev_ts) * (g.rn::float8 / (g.cnt + 1)))
  WHEN g.next_ts IS NOT NULL THEN
    g.next_ts - ((g.cnt - g.rn + 1) * interval '1 minute')
  ELSE now()
END
FROM grouped g
WHERE t.log_id = g.log_id;
