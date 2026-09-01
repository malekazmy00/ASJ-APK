// supabase/functions/login-user/index.ts
//
// يطابق منطق core/security.py الأصلي (argon2-cffi PasswordHasher، صيغة
// PHC القياسية) — نتحقق هنا بنفس الخوارزمية عبر مكتبة hash-wasm
// (WASM نقي، متوافق مع Deno Edge Runtime بدون أي بناء أصلي/native).
//
// يستخدم SERVICE_ROLE key (متاح تلقائياً كمتغير بيئة داخل أي Edge
// Function على Supabase) عشان يقدر يقرأ عمود password، حتى لو الـ RLS
// اتشدد مستقبلاً على anon key.

import { createClient } from "npm:@supabase/supabase-js@2";
import { argon2Verify } from "npm:hash-wasm@4";
import { signAppToken, type AppRole } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const { username, password } = await req.json();

    if (!username || !password) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: user, error } = await supabase
      .from("users")
      .select(
        "username, password, role, can_export, can_track, can_edit, status",
      )
      .eq("username", username)
      .maybeSingle();

    if (error || !user) {
      return jsonResponse({ success: false, error: "بيانات دخول غير صحيحة" }, 401);
    }

    if (user.status && user.status !== "Active") {
      return jsonResponse({ success: false, error: "الحساب غير مفعّل" }, 403);
    }

    const isValid = await argon2Verify({
      password,
      hash: user.password,
    });

    if (!isValid) {
      return jsonResponse({ success: false, error: "بيانات دخول غير صحيحة" }, 401);
    }

    // تسجيل الدخول في اللوج + تحديث last_login (بدون انتظار الفشل يوقف الاستجابة)
    // TASK-020: timestamp صراحة (defense-in-depth فوق DEFAULT now()
    // المضاف في migrations/020) — بدون ده كانت كل صفوف LOGIN (100%)
    // بترجع NULL.
    await supabase.from("transactions_log").insert({
      item_id: null,
      action_type: "LOGIN",
      username: user.username,
      details: "تسجيل دخول",
      timestamp: new Date().toISOString(),
    });
    await supabase
      .from("users")
      .update({ last_login: new Date().toISOString() })
      .eq("username", user.username);

    const { password: _omit, ...safeUser } = user;

    // بعد نجاح التحقق فعلياً (Argon2)، نولّد توكن موقّع من السيرفر —
    // ده اللي هيتحقق منه أي Edge Function حساسة لاحقاً (requireAuth/
    // requireRole)، بدل ما تثق في أي username جاي في الـ body.
    const token = await signAppToken({
      username: user.username,
      role: (user.role as AppRole) ?? "worker",
    });

    return jsonResponse({ success: true, user: safeUser, token }, 200);
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
