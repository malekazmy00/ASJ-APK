// supabase/functions/change-password/index.ts
//
// تغيير كلمة مرور المستخدم الحالي بنفسه (يحتاج كلمة المرور القديمة
// صح الأول). نفس منطق الهاش المستخدم في admin-create-user
// (argon2id) ونفس منطق التحقق المستخدم في login-user (argon2Verify).

import { createClient } from "npm:@supabase/supabase-js@2";
import { argon2Verify, argon2id } from "npm:hash-wasm@4";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const { username, oldPassword, newPassword } = await req.json();

    if (!username || !oldPassword || !newPassword) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }
    if (String(newPassword).length < 6) {
      return jsonResponse(
        { success: false, error: "كلمة المرور الجديدة قصيرة جداً (٦ أحرف على الأقل)" },
        400,
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: user, error } = await supabase
      .from("users")
      .select("username, password")
      .eq("username", username)
      .maybeSingle();

    if (error || !user) {
      return jsonResponse({ success: false, error: "مستخدم غير موجود" }, 404);
    }

    const isValid = await argon2Verify({ password: oldPassword, hash: user.password });
    if (!isValid) {
      return jsonResponse({ success: false, error: "كلمة المرور الحالية غير صحيحة" }, 401);
    }

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

    const { error: updateError } = await supabase
      .from("users")
      .update({ password: newHash })
      .eq("username", username);

    if (updateError) {
      return jsonResponse({ success: false, error: updateError.message }, 400);
    }

    await supabase.from("transactions_log").insert({
      item_id: null,
      action_type: "UPDATE",
      username,
      details: "تغيير كلمة المرور الشخصية",
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