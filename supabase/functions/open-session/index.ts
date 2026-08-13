// supabase/functions/open-session/index.ts
//
// فتح جلسة دخول جديدة. الفرق عن إدراج مباشر من التطبيق: الـ IP بتاع
// المستخدم مش متاح للتطبيق نفسه يعرفه بشكل موثوق (ده رقم الجهاز
// بالنسبة للشبكة اللي بيوصل بيها، مش حاجة التطبيق بيعرفها) — لازم
// يتقرا من الـ request headers على السيرفر، فمحتاج Edge Function
// بدل إدراج مباشر لجدول user_sessions.

import { createClient } from "npm:@supabase/supabase-js@2";
import { requireAuth, authErrorResponse } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    // TASK-303: الـ username بيتاخد من التوكن الموقّع بس — مش من
    // الـ body. قبل كده أي حد يعرف الـ endpoint كان يقدر يفتح session
    // باسم أي مستخدم (حتى admin) بمجرد بعت username في الطلب.
    const identity = await requireAuth(req);
    const { deviceInfo } = await req.json();

    // x-forwarded-for بيحتوي على IP العميل الحقيقي غالباً كأول قيمة
    // في القايمة (باقي القيم بتاعة أي بروكسي وسيط)
    const forwardedFor = req.headers.get("x-forwarded-for");
    const ip = forwardedFor ? forwardedFor.split(",")[0].trim() : null;

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data, error } = await supabase
      .from("user_sessions")
      .insert({
        username: identity.username,
        device_info: deviceInfo ?? null,
        ip_address: ip,
      })
      .select("id")
      .single();

    if (error) {
      return jsonResponse({ success: false, error: error.message }, 400);
    }

    return jsonResponse({ success: true, sessionId: data.id }, 200);
  } catch (e) {
    return authErrorResponse(e);
  }
});

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}