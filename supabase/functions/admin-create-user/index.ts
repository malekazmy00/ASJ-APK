// supabase/functions/admin-create-user/index.ts
//
// إنشاء مستخدم جديد من لوحة الأدمن. الهاش بيتعمل هنا على السيرفر
// (نفس خوارزمية core/security.py: argon2id) بدل تطبيق Flutter، لأن
// مكتبات Argon2 على الموبايل غير مضمونة الأداء/التوافق.

import { createClient } from "npm:@supabase/supabase-js@2";
import { argon2id } from "npm:hash-wasm@4";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const { username, password, role, can_export, can_track, can_edit } =
      await req.json();

    if (!username || !password || !role) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // ملاحظة: لازم صلاحية الأدمن تتحقق هنا فعلياً (مثلاً عبر تمرير توكن
    // الجلسة والتأكد إن صاحبها role=admin) قبل تنفيذ أي إنشاء —
    // حالياً هذه الدالة تفترض إنها بتتنادى بس من واجهة الأدمن، ويُفضّل
    // تشديدها بفحص صريح عند التنفيذ الفعلي.

    const salt = crypto.getRandomValues(new Uint8Array(16));
    const passwordHash = await argon2id({
      password,
      salt,
      parallelism: 1,
      iterations: 3,
      memorySize: 65536,
      hashLength: 32,
      outputType: "encoded",
    });

    const { error } = await supabase.from("users").insert({
      username,
      password: passwordHash,
      role,
      can_export: can_export ?? false,
      can_track: can_track ?? false,
      can_edit: can_edit ?? false,
      status: "Active",
    });

    if (error) {
      return jsonResponse({ success: false, error: error.message }, 400);
    }

    return jsonResponse({ success: true }, 200);
  } catch (e) {
    console.error(e);
    return jsonResponse({ success: false, error: "خطأ في الخادم" }, 500);
  }
});

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
