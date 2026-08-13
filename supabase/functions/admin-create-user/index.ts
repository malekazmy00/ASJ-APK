// supabase/functions/admin-create-user/index.ts
//
// إنشاء مستخدم جديد من لوحة الأدمن. الهاش بيتعمل هنا على السيرفر
// (نفس خوارزمية core/security.py: argon2id) بدل تطبيق Flutter، لأن
// مكتبات Argon2 على الموبايل غير مضمونة الأداء/التوافق.

import { createClient } from "npm:@supabase/supabase-js@2";
import { argon2id } from "npm:hash-wasm@4";
import { requireRole, authErrorResponse } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    // TASK-301: صلاحية الأدمن بتتحقق هنا فعلياً دلوقتي — مش افتراض.
    // أي مستدعي مش معاه توكن admin صالح بياخد 401/403 قبل أي تنفيذ.
    const admin = await requireRole(req, "admin");

    const { username, password, role, can_export, can_track, can_edit } =
      await req.json();

    if (!username || !password || !role) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

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
      created_by: admin.username,
    });

    if (error) {
      return jsonResponse({ success: false, error: error.message }, 400);
    }

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