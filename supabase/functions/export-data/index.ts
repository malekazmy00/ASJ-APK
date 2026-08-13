// supabase/functions/export-data/index.ts
//
// TASK-322: التصدير قبل كده كان بيعتمد بالكامل على can_export في
// الواجهة بس (ExportRepository كان بيسأل الجداول مباشرة بمفتاح anon —
// لو حد عدّل التطبيق محلياً أو نادى نفس الجدول بطريقة تانية، مفيش أي
// تحقق سيرفر حقيقي كان بيمنعه). دلوقتي أي طلب تصدير لازم:
//   1. توكن دخول صالح (requireAuth).
//   2. can_export = true لصاحب التوكن (أو يكون admin، زي باقي المشروع).
// وبيتسجل Audit مستقل عن أي log بيبعته العميل، عشان نعرف مين صدّر
// ايه وإمتى حتى لو العميل نفسه اتعدّل أو فشل يسجل من ناحيته.

import { createClient } from "npm:@supabase/supabase-js@2";
import { requireAuth, authErrorResponse } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// deno-lint-ignore no-explicit-any
type QueryFilter = (q: any) => any;

const DATASETS: Record<
  string,
  { table: string; order: string; ascending?: boolean; filter?: QueryFilter }
> = {
  full: { table: "inventory_items", order: "item_id" },
  available: {
    table: "inventory_items",
    order: "item_id",
    filter: (q) => q.eq("status", "Available"),
  },
  dispatched: {
    table: "inventory_items",
    order: "item_id",
    filter: (q) => q.eq("status", "Out"),
  },
  kb: { table: "specs_knowledge_base", order: "Part_Number" },
  log: { table: "transactions_log", order: "timestamp", ascending: false },
};

Deno.serve(async (req) => {
  try {
    const identity = await requireAuth(req);
    const { dataset } = await req.json();

    const config = DATASETS[dataset];
    if (!config) {
      return jsonResponse({ success: false, error: "نوع تقرير غير معروف" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // الأدمن مسموح له دايماً (زي باقي التطبيق) — أي دور تاني لازم
    // يكون عنده can_export = true فعلياً على السيرفر.
    if (identity.role !== "admin") {
      const { data: user } = await supabase
        .from("users")
        .select("can_export")
        .eq("username", identity.username)
        .maybeSingle();
      if (!user?.can_export) {
        return jsonResponse({ success: false, error: "مفيش صلاحية تصدير لهذا الحساب" }, 403);
      }
    }

    let query = supabase.from(config.table).select();
    if (config.filter) query = config.filter(query);
    const { data, error } = await query.order(config.order, {
      ascending: config.ascending ?? true,
    });

    if (error) {
      return jsonResponse({ success: false, error: error.message }, 400);
    }

    // Audit مستقل عن أي تسجيل بيعمله العميل من ناحيته — يوثّق مين
    // صدّر ايه وكام صف، من غير ما يعتمد على إن العميل نجح يسجّله.
    await supabase.from("transactions_log").insert({
      item_id: null,
      action_type: "EXPORT",
      username: identity.username,
      details: `تصدير: ${dataset} (${data?.length ?? 0} صف)`,
    });

    return jsonResponse({ success: true, rows: data }, 200);
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
