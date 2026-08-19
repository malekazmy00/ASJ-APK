-- 018_notification_and_session_fixes.sql
--
-- تجميع 5 إصلاحات مكتشفة أثناء مراجعة "الإشعارات مش بتظهر للعامل/
-- المهندس" على قاعدة الإنتاج بعد النقل (project ref
-- boifbtoaccfjnzifnwkp):
--
--   1) admin_notifications.timestamp من غير DEFAULT ومن غير أي مسار
--      إدراج بيحددها صراحة → كل الصفوف الموجودة (159 وقت الفحص)
--      timestamp بتاعتها NULL، فـ ORDER BY timestamp DESC في
--      NotificationRepository.getRecent() بلا معنى فعلي.
--   2) Backfill لنفس الصفوف دي بقيمة زمنية معقولة بدل NULL.
--   3) update_item_basic_fields_tx (تعديل بيانات أساسية من
--      update-item-fields) مفيهاش أي منطق إشعار خالص — تعديلات
--      العامل/المهندس للحقول الأساسية ما كانتش بتوصل للأدمن أصلاً.
--   4) نفس مشكلة (1) بالظبط على engineer_queries.timestamp — DEFAULT
--      مفقود بعد النقل (كان TIMESTAMPTZ DEFAULT now() في
--      000_missing_base_schema.sql، والعمود الحي دلوقتي TIMESTAMP من
--      غير DEFAULT خالص) — عطل كامن هيضرب أول استعلام مهندس جديد.
--   5) user_sessions.ip_address غير موجود خالص على قاعدة الإنتاج
--      (كان موجود في نية الكود بس مش في الـ schema الفعلي) — سبب
--      FunctionsHttpException 400 على كل تسجيل دخول من 15 أغسطس
--      (Sentry FLUTTER-2/FLUTTER-3)، وده بيمنع فتح session (تتبع
--      الخمول/تسجيل الخروج التلقائي) بصمت مع كل عملية دخول.
--
-- شغّلها يدوياً على Supabase SQL Editor (أو أي أداة migration بتفضّلها)
-- — آمنة تتكرر بالكامل (idempotent) زي باقي ملفات المشروع، تقدر تشغّلها
-- أكتر من مرة من غير أي أثر جانبي إضافي.

-- ============================================================
-- 1) admin_notifications.timestamp — DEFAULT now()
-- ============================================================
ALTER TABLE admin_notifications ALTER COLUMN "timestamp" SET DEFAULT now();

-- ============================================================
-- 2) Backfill الصفوف القديمة اللي timestamp بتاعتها NULL
-- ============================================================
-- 2.أ) أول محاولة: ربط حقيقي بوقت العملية الفعلية عن طريق related_id
--     (= item_id) مقابل transactions_log، حسب نوع الإشعار. ده بيغطي
--     الغالبية العظمى (part_entry/dispatch/return كلهم مرتبطين بقطعة
--     واحدة اتسجلت ليها حركة واحدة بالظبط في نفس اللحظة).
UPDATE admin_notifications an
SET "timestamp" = t."timestamp"
FROM transactions_log t
WHERE an."timestamp" IS NULL
  AND an.notif_type = 'part_entry'
  AND an.related_id = t.item_id
  AND t.action_type = 'INSERT';

UPDATE admin_notifications an
SET "timestamp" = t."timestamp"
FROM transactions_log t
WHERE an."timestamp" IS NULL
  AND an.notif_type = 'dispatch'
  AND an.related_id = t.item_id
  AND t.action_type = 'OUT';

UPDATE admin_notifications an
SET "timestamp" = t."timestamp"
FROM transactions_log t
WHERE an."timestamp" IS NULL
  AND an.notif_type = 'return'
  AND an.related_id = t.item_id
  AND t.action_type = 'RETURN';

-- 2.ب) أي صف لسه NULL بعد المحاولة فوق (زي permissions_changed اللي
--     مالوش related_id أصلاً) — بيتوزّع بالتساوي زمنياً بين أقرب صف
--     قبله وأقرب صف بعده (بترتيب notif_id) اللي بقى ليهم timestamp
--     حقيقي من الخطوة (2.أ). كده الترتيب النهائي بيفضل متسق مع تسلسل
--     notif_id (اللي هو بالتعريف تسلسل زمني صحيح، BIGSERIAL) حتى لو
--     القيمة المطلقة تقريبية.
WITH gaps AS (
  SELECT
    notif_id,
    "timestamp",
    MAX("timestamp") OVER (ORDER BY notif_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS prev_ts,
    MIN("timestamp") OVER (ORDER BY notif_id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS next_ts
  FROM admin_notifications
),
grouped AS (
  SELECT
    notif_id, prev_ts, next_ts,
    ROW_NUMBER() OVER (PARTITION BY prev_ts, next_ts ORDER BY notif_id) AS rn,
    COUNT(*) OVER (PARTITION BY prev_ts, next_ts) AS cnt
  FROM gaps
  WHERE "timestamp" IS NULL
)
UPDATE admin_notifications an
SET "timestamp" = CASE
  WHEN g.prev_ts IS NOT NULL AND g.next_ts IS NOT NULL THEN
    g.prev_ts + ((g.next_ts - g.prev_ts) * (g.rn::float8 / (g.cnt + 1)))
  WHEN g.prev_ts IS NOT NULL THEN
    g.prev_ts + (g.rn * interval '1 minute')
  WHEN g.next_ts IS NOT NULL THEN
    g.next_ts - ((g.cnt - g.rn + 1) * interval '1 minute')
  ELSE now()
END
FROM grouped g
WHERE an.notif_id = g.notif_id;

-- ============================================================
-- 3.أ) الدوال الثلاثة اللي بتنشئ إشعار: تحديد timestamp = now() صراحة
--     (defense-in-depth فوق الـ DEFAULT من الخطوة 1 — لو حد يوم عمل
--     migration تانية شالت الـ DEFAULT بالغلط، الكود نفسه لسه سليم)
-- ============================================================
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
  -- timestamp بتتحدد هنا صراحة (018) — مش هتتوقف على DEFAULT العمود بس.
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
      INSERT INTO admin_notifications (message, notif_type, related_id, "timestamp")
      VALUES (p_notif_message, 'dispatch', p_item_id, now());
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
      INSERT INTO admin_notifications (message, notif_type, related_id, "timestamp")
      VALUES (p_notif_message, 'return', p_item_id, now());
    END IF;
  END IF;

  RETURN v_item;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_inventory_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION dispatch_item_tx FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION return_item_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION create_inventory_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION dispatch_item_tx TO service_role;
GRANT EXECUTE ON FUNCTION return_item_tx TO service_role;

-- ============================================================
-- 3.ب) update_item_basic_fields_tx — إضافة منطق إشعار جديد بالكامل
--     (مكانش موجود في أي نسخة سابقة). إشعار واحد لكل نداء للدالة —
--     مهما كان عدد الحقول اللي اتغيّرت في نفس الطلب (location/
--     condition/ownership/status/notes/serial)، لأن الدالة كلها
--     execution واحد = INSERT واحد بس هنا. الرسالة بتتبني من
--     p_username وp_item_id مباشرة (السيرفر، مش الفلاتر) لأن
--     update-item-fields الحالية مالهاش أي notifMessage بيتبعت من
--     العميل أصلاً.
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
  v_notif_enabled BOOLEAN;
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

  -- إشعار جديد (018): notif_type = 'field_update' — إشعار واحد لكل
  -- نداء، بغض النظر عن عدد الحقول المتغيرة في نفس الطلب.
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

REVOKE EXECUTE ON FUNCTION update_item_basic_fields_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION update_item_basic_fields_tx TO service_role;

-- تسجيل نوع الإشعار الجديد في notification_settings عشان يظهر افتراضياً
-- (مفعّل) في شاشة إعدادات الإشعارات بتاعة الأدمن — نفس نمط 004_round3.sql.
INSERT INTO notification_settings (notif_type, enabled) VALUES
    ('field_update', true)
ON CONFLICT (notif_type) DO NOTHING;

-- ============================================================
-- 4) engineer_queries.timestamp — نفس إصلاح البند (1)، وترجيع النوع
--    لـ TIMESTAMPTZ زي ما كان مفروض من الأصل في 000_missing_base_schema.sql
--    (اتفقد الاتنين — النوع والـ DEFAULT — في وقت النقل). التحويل من
--    TIMESTAMP لـ TIMESTAMPTZ آمن هنا: البيانات الحالية (31 صف وقت
--    الفحص) قيمها كلها فعلية ومتصلة، والتحويل بيفترض إنها كانت مسجّلة
--    بتوقيت UTC (زي باقي أعمدة TIMESTAMPTZ في المشروع اللي بتعتمد على
--    DEFAULT now()) — الفحص بالـ IF جوه الـ DO block بيمنع أي تكرار
--    غير آمن لو اتشغلت الملف أكتر من مرة أو لو حد سبقنا وصلّح النوع يدوياً.
DO $$
BEGIN
  IF (
    SELECT data_type FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'engineer_queries' AND column_name = 'timestamp'
  ) = 'timestamp without time zone' THEN
    ALTER TABLE engineer_queries
      ALTER COLUMN "timestamp" TYPE TIMESTAMPTZ USING "timestamp" AT TIME ZONE 'UTC';
  END IF;
END $$;

ALTER TABLE engineer_queries ALTER COLUMN "timestamp" SET DEFAULT now();

-- ============================================================
-- 5) user_sessions.ip_address — العمود ده متوقّع فعلياً من
--    supabase/functions/open-session/index.ts (بيبعت ip كـ TEXT عادي
--    مستخرج من x-forwarded-for)، لكنه مش موجود خالص في الـ schema الحي
--    — ده سبب FunctionsHttpException 400 على كل تسجيل دخول من 15
--    أغسطس (Sentry FLUTTER-2/FLUTTER-3). TEXT مش INET عمداً: القيمة
--    ممكن تبقى IP واحد أو حتى فاضية (x-forwarded-for مش دايماً موجود
--    أو ممكن يكون فورمات غريب لو فيه بروكسي وسيط)، ومفيش أي معالجة/
--    تحقق نوع IP في الكود الحالي — TEXT بسيط زي device_info بالظبط.
ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS ip_address TEXT;

-- تحديث فوري لـ schema cache بتاعة PostgREST بدل ما نستنى الـ listener
-- الدوري — آمن يتكرر، مفيش أي تأثير لو الكاش أصلاً محدّث.
NOTIFY pgrst, 'reload schema';
