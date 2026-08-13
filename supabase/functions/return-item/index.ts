// supabase/functions/return-item/index.ts
//
// راجع migrations/013_dispatch_return_atomic.sql — نفس نمط
// dispatch-item بالظبط، لعملية الاسترجاع.

import { createClient } from "npm:@supabase/supabase-js@2";
import { requireAuth, authErrorResponse } from "../_shared/auth.ts";
import { rpcErrorResponse } from "../_shared/errors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const identity = await requireAuth(req);
    const { itemId, details, notifMessage } = await req.json();

    if (!itemId || !details) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const { data, error } = await supabase.rpc("return_item_tx", {
      p_item_id: itemId,
      p_username: identity.username,
      p_details: details,
      p_notif_message: notifMessage ?? null,
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
