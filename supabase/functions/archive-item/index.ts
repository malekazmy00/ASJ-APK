// supabase/functions/archive-item/index.ts
//
// راجع migrations/015_archive_atomic.sql. آخر عملية من مصفوفة
// SECURITY.md — نفس نمط update-item-fields بالظبط: requireAuth + فحص
// can_edit فعلي (الأدمن مسموح له دايماً) + RPC ذرية ممنوعة من anon.

import { createClient } from "npm:@supabase/supabase-js@2";
import { requireAuth, authErrorResponse, AuthError } from "../_shared/auth.ts";
import { rpcErrorResponse } from "../_shared/errors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const identity = await requireAuth(req);
    const { itemId, reason } = await req.json();

    if (!itemId || !reason) {
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
        throw new AuthError("مفيش صلاحية أرشفة لهذا الحساب", 403);
      }
    }

    const { data, error } = await supabase.rpc("archive_item_tx", {
      p_item_id: itemId,
      p_deleted_by: identity.username,
      p_reason: reason,
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
