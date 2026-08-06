// supabase/functions/admin-reset-password/index.ts
//
// إعادة تعيين كلمة مرور مستخدم تاني من لوحة الأدمن — بدون الحاجة
// لكلمة المرور القديمة (عكس change-password اللي للمستخدم نفسه).
// نفس منطق الهاش المستخدم في admin-create-user.
//
// ملاحظة أمان (نفس ملاحظة admin-create-user بالظبط): الدالة دي
// بتفترض حالياً إنها بتتنادى من واجهة الأدمن بس، ويُفضّل تشديدها
// بفحص صريح لصلاحية الأدمن عند التنفيذ الفعلي.

import { createClient } from "npm:@supabase/supabase-js@2";
import { argon2id } from "npm:hash-wasm@4";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const { username, newPassword } = await req.json();

    if (!username || !newPassword) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }
    if (String(newPassword).length < 6) {
      return jsonResponse(
        { success: false, error: "كلمة المرور قصيرة جداً (٦ أحرف على الأقل)" },
        400,
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const salt = crypto.getRandomValues(new Uint8Array(16));
    const newHash = await argon2id({
      password: newPassword,
      salt,
      parallelism: 1,
      iterations: 3,
      memorySize: 65536,
      hashLength: 32,
      outputType: "encoded",
    });

    const { error } = await supabase
      .from("users")
      .update({ password: newHash })
      .eq("username", username);

    if (error) {
      return jsonResponse({ success: false, error: error.message }, 400);
    }

    await supabase.from("transactions_log").insert({
      item_id: null,
      action_type: "USER_MGMT",
      username,
      details: "إعادة تعيين كلمة المرور بواسطة الأدمن",
    });

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