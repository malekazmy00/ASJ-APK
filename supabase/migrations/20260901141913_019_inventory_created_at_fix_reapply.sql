ALTER TABLE inventory_items ALTER COLUMN created_at SET DEFAULT now();

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

  INSERT INTO transactions_log (item_id, action_type, username, details)
  VALUES (v_item.item_id, 'INSERT', p_username, p_log_details);

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

REVOKE EXECUTE ON FUNCTION create_inventory_item_tx FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION create_inventory_item_tx TO service_role;

WITH gaps AS (
  SELECT
    item_id,
    created_at,
    MAX(created_at) OVER (ORDER BY item_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS prev_ts,
    MIN(created_at) OVER (ORDER BY item_id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS next_ts
  FROM inventory_items
),
grouped AS (
  SELECT
    item_id, prev_ts, next_ts,
    ROW_NUMBER() OVER (PARTITION BY prev_ts, next_ts ORDER BY item_id) AS rn,
    COUNT(*) OVER (PARTITION BY prev_ts, next_ts) AS cnt
  FROM gaps
  WHERE created_at IS NULL
)
UPDATE inventory_items i
SET created_at = CASE
  WHEN g.prev_ts IS NOT NULL AND g.next_ts IS NOT NULL THEN
    g.prev_ts + ((g.next_ts - g.prev_ts) * (g.rn::float8 / (g.cnt + 1)))
  WHEN g.prev_ts IS NOT NULL THEN
    g.prev_ts + ((now() - g.prev_ts) * (g.rn::float8 / (g.cnt + 1)))
  WHEN g.next_ts IS NOT NULL THEN
    g.next_ts - ((g.cnt - g.rn + 1) * interval '1 minute')
  ELSE now()
END
FROM grouped g
WHERE i.item_id = g.item_id;

