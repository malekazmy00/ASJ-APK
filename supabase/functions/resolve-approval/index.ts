// supabase/functions/resolve-approval/index.ts
//
// الأدمن يوافق أو يرفض طلب معلّق (تعديل رقم قطعة/سريال، أو استيراد
// قاعدة معرفة). لو موافقة، الدالة دي هي اللي بتطبّق التغيير فعلياً
// وتسجّله في transactions_log.

import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const { approvalId, action, resolvedBy } = await req.json();

    if (!approvalId || !action || !resolvedBy) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }
    if (action !== "approve" && action !== "reject") {
      return jsonResponse({ success: false, error: "action غير معروف" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: approval, error: fetchError } = await supabase
      .from("pending_approvals")
      .select("*")
      .eq("id", approvalId)
      .maybeSingle();

    if (fetchError || !approval) {
      return jsonResponse({ success: false, error: "الطلب غير موجود" }, 404);
    }
    if (approval.status !== "Pending") {
      return jsonResponse({ success: false, error: "الطلب ده اتحسم قبل كده" }, 409);
    }

    if (action === "reject") {
      await supabase
        .from("pending_approvals")
        .update({ status: "Rejected", resolved_by: resolvedBy, resolved_at: new Date().toISOString() })
        .eq("id", approvalId);
      await supabase.from("transactions_log").insert({
        item_id: approval.payload?.itemId ?? null,
        action_type: "USER_MGMT",
        username: resolvedBy,
        details: `تم رفض طلب: ${approval.approval_type}`,
      });
      return jsonResponse({ success: true }, 200);
    }

    // action === "approve": نطبّق التغيير الفعلي حسب النوع
    const payload = approval.payload ?? {};

    if (approval.approval_type === "part_number_edit") {
      await supabase
        .from("inventory_items")
        .update({ part_number: payload.newPartNumber })
        .eq("item_id", payload.itemId);
    } else if (approval.approval_type === "serial_edit") {
      await supabase
        .from("inventory_items")
        .update({ serial_number: payload.newSerial })
        .eq("item_id", payload.itemId);
    } else if (approval.approval_type === "kb_import") {
      const rows = payload.rows ?? [];
      const batchSize = 500;
      for (let i = 0; i < rows.length; i += batchSize) {
        const batch = rows.slice(i, i + batchSize);
        await supabase.from("specs_knowledge_base").upsert(batch, { onConflict: "Part_Number" });
      }
    } else {
      return jsonResponse({ success: false, error: "نوع طلب غير مدعوم" }, 400);
    }

    await supabase
      .from("pending_approvals")
      .update({ status: "Approved", resolved_by: resolvedBy, resolved_at: new Date().toISOString() })
      .eq("id", approvalId);

    await supabase.from("transactions_log").insert({
      item_id: payload.itemId ?? null,
      action_type: "USER_MGMT",
      username: resolvedBy,
      details: `تمت الموافقة على طلب: ${approval.approval_type} (طلبه: ${approval.requested_by})`,
    });

    return jsonResponse({ success: true }, 200);
  } catch (e) {
    console.error(e);
    return jsonResponse({ success: false, error: `خطأ في الخادم: ${e}` }, 500);
  }
});

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}