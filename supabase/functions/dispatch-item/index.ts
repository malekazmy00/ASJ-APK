// supabase/functions/dispatch-item/index.ts
//
// راجع migrations/013_dispatch_return_atomic.sql — نفس نمط
// create-inventory-item بالظبط: requireAuth الأول، بعدين نداء الـ RPC
// (اللي بقت ممنوعة من anon) بمفتاح service_role. username الفاعل
// بيتحدد من التوكن نفسه، مش من الـ body.

import { createClient } from "npm:@supabase/supabase-js@2";
import { requireAuth, authErrorResponse } from "../_shared/auth.ts";
import { rpcErrorResponse } from "../_shared/errors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// لازم تطابق dbValue بتاعة enum ExitType في lib/core/models/enums.dart
// بالظبط — أي قيمة تانية مرفوضة هنا قبل ما توصل حتى لقاعدة البيانات.
const ALLOWED_EXIT_TYPES = ["Sale", "Loan", "Damaged"];

Deno.serve(async (req) => {
  try {
    const identity = await requireAuth(req);
    const { itemId, details, exitType, notifMessage } = await req.json();

    if (!itemId || !details || !exitType) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }
    if (!ALLOWED_EXIT_TYPES.includes(exitType)) {
      return jsonResponse({ success: false, error: "سبب صرف غير معروف" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const { data, error } = await supabase.rpc("dispatch_item_tx", {
      p_item_id: itemId,
      p_username: identity.username,
      p_details: details,
      p_exit_type: exitType,
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
