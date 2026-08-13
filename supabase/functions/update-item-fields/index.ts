// supabase/functions/update-item-fields/index.ts
//
// راجع migrations/014_update_fields_atomic.sql. زيادة عن نمط
// create-inventory-item/dispatch-item: هنا كمان بنتحقق من صلاحية
// can_edit فعلياً على السيرفر (مش بس requireAuth) — قبل كده كانت
// شاشات can_edit بتتحكم في إظهار/إخفاء الزرار في الواجهة بس، من غير
// أي تحقق مستقل. الأدمن مسموح له دايماً زي باقي المشروع.

import { createClient } from "npm:@supabase/supabase-js@2";
import { requireAuth, authErrorResponse, AuthError } from "../_shared/auth.ts";
import { rpcErrorResponse } from "../_shared/errors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const identity = await requireAuth(req);
    const body = await req.json();

    if (!body.itemId) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    if (identity.role !== "admin") {
      const { data: user } = await supabase
        .from("users")
        .select("can_edit")
        .eq("username", identity.username)
        .maybeSingle();
      if (!user?.can_edit) {
        throw new AuthError("مفيش صلاحية تعديل لهذا الحساب", 403);
      }
    }

    const { data, error } = await supabase.rpc("update_item_basic_fields_tx", {
      p_item_id: body.itemId,
      p_username: identity.username,
      p_location: body.location ?? null,
      p_condition: body.condition ?? null,
      p_ownership_status: body.ownershipStatus ?? null,
      p_status: body.status ?? null,
      p_update_status: !!body.updateStatus,
      p_notes: body.notes ?? null,
      p_update_notes: !!body.updateNotes,
      p_serial_number: body.serialNumber ?? null,
      p_update_serial: !!body.updateSerial,
      p_log_details: body.logDetails ?? "تعديل بيانات أساسية",
    });

    if (error) {
      return rpcErrorResponse(error);
    }

    return jsonResponse({ success: true, item: data }, 200);
  } catch (e) {
    return authErrorResponse(e);
  }
});

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
