-- 011_grouped_inventory_rpc.sql
-- TASK-315: تجميع المخزون (تبويب المخزون + جزء التوفر في تبويب البحث)
-- كان بيتم بالكامل في Dart — بيسحب كل صف مطابق من inventory_items
-- للجهاز، وبعدين يجمّعهم ويحسب العدّادات هناك. مع مخزون كبير (آلاف
-- القطع)، ده استهلاك بيانات وذاكرة غير ضروري على الموبايل.
--
-- الدالة دي بتعمل نفس التجميع بالظبط (نفس مفتاح التجميع: رقم القطعة
-- لو موجود، وإلا الوصف بعد التريم أو "غير محدد") لكن جوه Postgres —
-- الراجع للتطبيق بقى عدد "المجموعات" بس، مش كل القطع الفردية.
--
-- ملحوظة: فلترة "سبب الصرف" (exit_type) لسه بتتم في Dart زي ما هي —
-- محتاجة ربط مع transactions_log لآخر حركة صرف لكل قطعة، وهي مسار
-- أضيق استخداماً، فسيبناها زي ما هي تقليلاً لمخاطر أي فرق سلوك دقيق.
--
-- شغّلها يدوياً على Supabase SQL Editor. آمنة تتكرر (CREATE OR REPLACE).

CREATE OR REPLACE FUNCTION get_grouped_inventory(
  p_presence TEXT DEFAULT NULL,          -- 'available' | 'dispatched' | NULL (الكل)
  p_ownership_status TEXT DEFAULT NULL,  -- بيفعل مع 'available' بس، زي Dart بالظبط
  p_entry_type TEXT DEFAULT NULL
)
RETURNS TABLE (
  group_key TEXT,
  display_name TEXT,
  item_type TEXT,
  brand TEXT,
  has_part_number BOOLEAN,
  total_count BIGINT,
  available_count BIGINT,
  min_item_id INT,
  min_created_at TIMESTAMPTZ,
  max_updated_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
  WITH filtered AS (
    SELECT
      i.item_id,
      i.item_type,
      i.part_number,
      i.description,
      i.status,
      i.created_at,
      i.updated_at,
      (i.part_number IS NOT NULL AND i.part_number <> '' AND i.part_number <> 'PENDING') AS has_pn
    FROM inventory_items i
    WHERE i.status <> 'Archived'
      AND (
        p_presence IS NULL
        OR (p_presence = 'available' AND i.status <> 'Out'
            AND (p_ownership_status IS NULL OR i.ownership_status = p_ownership_status))
        OR (p_presence = 'dispatched' AND i.status = 'Out')
      )
      AND (p_entry_type IS NULL OR i.entry_type = p_entry_type)
  ),
  keyed AS (
    SELECT
      f.*,
      CASE
        WHEN f.has_pn THEN 'pn:' || f.part_number
        ELSE 'desc:' || COALESCE(NULLIF(TRIM(f.description), ''), 'غير محدد')
      END AS group_key
    FROM filtered f
  )
  SELECT
    k.group_key,
    COALESCE(
      MAX(kb."Part_Model"),
      MAX(CASE WHEN k.has_pn THEN k.part_number END),
      MAX(CASE WHEN NOT k.has_pn THEN COALESCE(NULLIF(TRIM(k.description), ''), 'غير محدد') END)
    ) AS display_name,
    MAX(k.item_type) AS item_type,
    MAX(kb."Brand") AS brand,
    BOOL_OR(k.has_pn) AS has_part_number,
    COUNT(*) AS total_count,
    COUNT(*) FILTER (WHERE k.status = 'Available') AS available_count,
    MIN(k.item_id) AS min_item_id,
    MIN(k.created_at) AS min_created_at,
    MAX(k.updated_at) AS max_updated_at
  FROM keyed k
  LEFT JOIN specs_knowledge_base kb ON k.has_pn AND kb."Part_Number" = k.part_number
  GROUP BY k.group_key;
$$;

GRANT EXECUTE ON FUNCTION get_grouped_inventory TO anon, authenticated;
