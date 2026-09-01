// supabase/functions/resolve-approval/index.ts
//
// الأدمن يوافق أو يرفض طلب معلّق (تعديل رقم قطعة/سريال، أو استيراد
// قاعدة معرفة). لو موافقة، الدالة دي هي اللي بتطبّق التغيير فعلياً
// وتسجّله في transactions_log.
//
// الجولة الثالثة (نقطة ١١): بعد الحسم (قبول أو رفض)، بيتسجل إشعار
// 'approval_resolved' — بيتفحص notification_settings الأول زي أي
// إشعار تاني، بنفس منطق NotificationRepository.create في الـ Flutter.

import { createClient } from "npm:@supabase/supabase-js@2";
import { requireRole, authErrorResponse } from "../_shared/auth.ts";
import { rpcErrorResponse } from "../_shared/errors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    // TASK-301: بس الأدمن يقدر يوافق/يرفض طلب معلّق. resolvedBy
    // بقت من التوكن الموقّع مش من الـ body.
    const admin = await requireRole(req, "admin");
    const resolvedBy = admin.username;
    const { approvalId, action } = await req.json();

    if (!approvalId || !action) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }
    if (action !== "approve" && action !== "reject") {
      return jsonResponse({ success: false, error: "action غير معروف" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // قبل كده: SELECT بيقرا status، بعدين IF بيتحقق، بعدين UPDATE
    // منفصلة — ده بالظبط نفس فئة مشكلة Race Condition اللي في
    // dispatch/return (لو طلبين موافقة/رفض جم في نفس اللحظة على نفس
    // الطلب، الاتنين كانوا يعدّوا فحص "لسه Pending" وينفذوا). دلوقتي
    // "المطالبة" بالطلب بقت UPDATE واحدة ذرية بشرط status='Pending'
    // (راجع claim_pending_approval_tx في
    // migrations/016_state_transition_guards.sql) — لو حد تاني كسبها
    // الأول، إحنا هنا هناخد BUSINESS_ERROR ونوقف فوراً.
    const newStatus = action === "reject" ? "Rejected" : "Approved";
    const { data: approval, error: claimError } = await supabase.rpc(
      "claim_pending_approval_tx",
      { p_approval_id: approvalId, p_new_status: newStatus, p_resolved_by: resolvedBy },
    );

    if (claimError) {
      return rpcErrorResponse(claimError);
    }

    if (action === "reject") {
      // TASK-020: timestamp صراحة (defense-in-depth فوق DEFAULT now()
      // المضاف في migrations/020).
      await supabase.from("transactions_log").insert({
        item_id: approval.payload?.itemId ?? null,
        action_type: "USER_MGMT",
        username: resolvedBy,
        details: `تم رفض طلب: ${approval.approval_type}`,
        timestamp: new Date().toISOString(),
      });
      await notifyIfEnabled(
        supabase,
        "approval_resolved",
        `${resolvedBy} رفض طلب ${approval.approval_type} (طلبه: ${approval.requested_by})`,
      );
      return jsonResponse({ success: true }, 200);
    }

    // action === "approve": نطبّق التغيير الفعلي حسب النوع. الطلب
    // بقى "بتاعنا" فعلياً بعد المطالبة الناجحة فوق، فمفيش خطر تكرار هنا.
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

    // TASK-020: timestamp صراحة (defense-in-depth فوق DEFAULT now()
    // المضاف في migrations/020).
    await supabase.from("transactions_log").insert({
      item_id: payload.itemId ?? null,
      action_type: "USER_MGMT",
      username: resolvedBy,
      details: `تمت الموافقة على طلب: ${approval.approval_type} (طلبه: ${approval.requested_by})`,
      timestamp: new Date().toISOString(),
    });

    await notifyIfEnabled(
      supabase,
      "approval_resolved",
      `${resolvedBy} وافق على طلب ${approval.approval_type} (طلبه: ${approval.requested_by})`,
    );

    return jsonResponse({ success: true }, 200);
  } catch (e) {
    return authErrorResponse(e);
  }
});

/// يسجّل إشعار جديد، لكن بيتجاهل بصمت لو النوع ده موقوف من الإعدادات —
/// نفس منطق NotificationRepository.create في الـ Flutter.
// deno-lint-ignore no-explicit-any
async function notifyIfEnabled(supabase: any, notifType: string, message: string) {
  try {
    const { data: setting } = await supabase
      .from("notification_settings")
      .select("enabled")
      .eq("notif_type", notifType)
      .maybeSingle();
    if (setting && setting.enabled === false) return;
    // TASK-018: timestamp صراحة (defense-in-depth فوق DEFAULT now()
    // المضاف في migrations/018) — نفس السبب بالظبط في NotificationRepository.create.
    await supabase
      .from("admin_notifications")
      .insert({ notif_type: notifType, message, timestamp: new Date().toISOString() });
  } catch (e) {
    console.error("notifyIfEnabled failed:", e);
  }
}

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}