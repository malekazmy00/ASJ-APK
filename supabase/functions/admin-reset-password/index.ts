// supabase/functions/admin-reset-password/index.ts
//
// إعادة تعيين كلمة مرور مستخدم تاني من لوحة الأدمن — بدون الحاجة
// لكلمة المرور القديمة (عكس change-password اللي للمستخدم نفسه).
// نفس منطق الهاش المستخدم في admin-create-user.
//
// TASK-301: صلاحية الأدمن بتتحقق هنا فعلياً دلوقتي (requireRole) —
// نفس الحل المطبّق في admin-create-user.

import { createClient } from "npm:@supabase/supabase-js@2";
import { argon2id } from "npm:hash-wasm@4";
import { requireRole, authErrorResponse } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const admin = await requireRole(req, "admin");

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
      .update({ password: newHash, password_changed_at: new Date().toISOString() })
      .eq("username", username);

    if (error) {
      return jsonResponse({ success: false, error: error.message }, 400);
    }

    // TASK-309: توكنات المستخدم القديمة (على أي جهاز) بقت مرفوضة
    // تلقائياً (راجع requireAuth)، وبنقفل سجلات جلساته المفتوحة كمان.
    await supabase.rpc("revoke_all_sessions", { p_username: username });

    await supabase.from("transactions_log").insert({
      item_id: null,
      action_type: "USER_MGMT",
      username,
      details: `إعادة تعيين كلمة المرور بواسطة الأدمن (${admin.username})`,
    });

    return jsonResponse({ success: true }, 200);
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