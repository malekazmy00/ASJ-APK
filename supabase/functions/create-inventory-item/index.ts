// supabase/functions/create-inventory-item/index.ts
//
// TASK-401: بديل آمن لنداء create_inventory_item_tx مباشرة من
// Flutter. الدالة دي بتتحقق من التوكن الأول (requireAuth — أي دور،
// مش أدمن بس، لأن تسجيل قطعة متاح لكل الأدوار بالتصميم الحالي)،
// وبعدين بس تنادي الـ RPC بمفتاح service_role (اللي بقى الوحيد
// المسموح له ينفّذها بعد 012_secure_atomic_insert_rpc.sql).
//
// username بيتحدد من التوكن نفسه (identity.username) مش من أي قيمة
// جايه في الـ body — نفس نمط TASK-303/change-password بالظبط.
//
// مراجعة إضافية: entryType/ownershipStatus/condition كلهم دروب-داون
// ثابت في الواجهة (مفيش نص حر ليهم) — بقوا محكومين بـ whitelist هنا.
// itemType عمداً مستثنى من الـ whitelist لأنه بيقبل نص حر فعلاً (اسم
// معدة الشغل بيتكتب يدوي) — بس بحد أقصى طول زي باقي الحقول النصية.

import { createClient } from "npm:@supabase/supabase-js@2";
import { requireAuth, authErrorResponse } from "../_shared/auth.ts";
import { requireOneOf, requireMaxLength, ValidationError } from "../_shared/validation.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const identity = await requireAuth(req);
    const body = await req.json();

    requireOneOf(body.entryType, ["Part", "Equipment"], "entryType", { required: true });
    requireOneOf(
      body.ownershipStatus,
      ["Owned", "Maintenance", "Custody", "Trial"],
      "ownershipStatus",
      { required: true },
    );
    requireOneOf(body.condition, ["جديدة", "مستعملة"], "condition");
    requireMaxLength(body.itemType, 200, "itemType");
    requireMaxLength(body.partNumber, 100, "partNumber");
    requireMaxLength(body.serialNumber, 100, "serialNumber");
    requireMaxLength(body.partModel, 100, "partModel");
    requireMaxLength(body.location, 300, "location");
    requireMaxLength(body.description, 1000, "description");
    requireMaxLength(body.notes, 1000, "notes");
    requireMaxLength(body.geminiInsights, 4000, "geminiInsights");

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data, error } = await supabase.rpc("create_inventory_item_tx", {
      p_item_type: body.itemType,
      p_part_number: body.partNumber,
      p_description: body.description ?? null,
      p_notes: body.notes ?? null,
      p_entry_type: body.entryType,
      p_location: body.location ?? null,
      p_condition: body.condition ?? null,
      p_serial_number: body.serialNumber ?? null,
      p_ownership_status: body.ownershipStatus,
      p_username: identity.username,
      p_gemini_insights: body.geminiInsights ?? null,
      p_part_model: body.partModel ?? null,
      p_log_details: body.logDetails ?? "",
      p_notif_message: body.notifMessage ?? null,
    });

    if (error) {
      return jsonResponse({ success: false, error: error.message }, 400);
    }

    return jsonResponse({ success: true, item: data }, 200);
  } catch (e) {
    if (e instanceof ValidationError) {
      return jsonResponse({ success: false, error: e.message }, 400);
    }
    return authErrorResponse(e);
  }
});

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
