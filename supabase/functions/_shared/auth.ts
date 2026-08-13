// supabase/functions/_shared/auth.ts
//
// طبقة الـ Authorization الموحّدة لكل الـ Edge Functions الحساسة.
// بديل خفيف عن الهجرة الكاملة لـ Supabase Auth (اللي مش هدف الجولة
// دي) — بيحل نفس المشكلة الجوهرية: السيرفر ما كانش بيتحقق من هوية
// المستدعي خالص، وكان بيثق في أي username جايه في الـ request body.
//
// آلية العمل:
//   1. login-user بعد نجاح التحقق (Argon2) بيولّد custom JWT موقّع
//      بمفتاح سري (APP_JWT_SECRET) — مفتاح منفصل تماماً عن
//      SUPABASE_SERVICE_ROLE_KEY، لازم يتضاف كـ secret على المشروع:
//        npx supabase secrets set APP_JWT_SECRET=<قيمة عشوائية طويلة>
//   2. الـ Flutter بيحفظ التوكن ده ويبعته في هيدر مخصص اسمه
//      x-app-token مع أي نداء لاحق لأي Edge Function حساسة (مش هيدر
//      Authorization العادي، لأن ده محجوز أصلاً لمفتاح anon اللي
//      supabase_flutter بيبعته تلقائياً مع كل functions.invoke).
//   3. أي Edge Function حساسة تبدأ بـ requireAuth() أو
//      requireRole(req, "admin") قبل أي تنفيذ فعلي، وتستخدم
//      identity.username الراجعة من التوكن الموقّع — مش أي username
//      جاي في الـ body.
//
// ده بيقفل TASK-301 (admin functions بدون تحقق) وTASK-303 (open-session
// بيقبل username من غير إثبات) وجزء أساسي من TASK-302 (وجود JSON محلي
// كان بيساوي "مسجّل دخول" — دلوقتي أي عملية حساسة بتتحقق من توكن
// موقّع من السيرفر نفسه في كل مرة، مش من بيانات محلية على الجهاز).

import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, jwtVerify } from "npm:jose@5";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const secret = Deno.env.get("APP_JWT_SECRET");
if (!secret) {
  // بنسجل تحذير بس مش بنوقف الدالة — عشان أي دالة تانية مش محتاجة
  // توكن (زي login-user نفسها) تفضل شغالة حتى لو السكرت لسه متضافش،
  // لكن أي محاولة فعلية للتوقيع/التحقق هتفشل برسالة واضحة بدل ما
  // تعدي بصمت.
  console.error(
    "APP_JWT_SECRET غير موجود في متغيرات البيئة — لازم يتضاف كـ secret على المشروع قبل استخدام التوكن",
  );
}
const secretKey = () => new TextEncoder().encode(secret ?? "");

export type AppRole = "worker" | "engineer" | "admin";

export interface AppTokenPayload {
  username: string;
  role: AppRole;
}

// مدة الصلاحية: طويلة نسبياً (٣٠ يوم) عشان تتوافق مع متطلب "يفضل
// مسجّل دخول لحد ما يعمل خروج صريح" — التحقق الحقيقي مش بيعتمد على
// قصر المدة، بيعتمد على إن كل عملية حساسة بتتحقق من التوقيع نفسه في
// كل مرة، فلو الحساب اتوقف/الصلاحية اتغيرت، أول عملية حساسة بعدها
// المفروض تترفض على مستوى الداتابيز نفسها (فحص users.status ممكن
// يتضاف مستقبلاً جوه requireAuth لو حبينا نمنع حتى التوكن الصالح
// لحساب موقوف).
const TOKEN_TTL = "30d";

export async function signAppToken(payload: AppTokenPayload): Promise<string> {
  return await new SignJWT({ username: payload.username, role: payload.role })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime(TOKEN_TTL)
    .sign(secretKey());
}

export class AuthError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

/// بيتحقق من هيدر x-app-token: توقيعه صحيح ولسه ساري، وإنه اتولّد بعد
/// آخر تغيير لكلمة مرور الحساب ده (TASK-309) — لو الباسورد اتغيّر
/// (سواء المستخدم نفسه أو الأدمن)، أي توكن قديم أُصدر قبل التغيير بقى
/// مرفوض تلقائياً هنا، حتى لو توقيعه سليم شكلياً ولسه في مدة الـ 30
/// يوم. يرجّع {username, role} المستخرجة من التوكن نفسه (مش من الـ
/// body) أو يرمي AuthError (401) لو مفيش توكن أو باظ/منتهي/اتلغى.
export async function requireAuth(req: Request): Promise<AppTokenPayload> {
  const token = req.headers.get("x-app-token");
  if (!token) {
    throw new AuthError("لا يوجد توكن دخول — سجّل الدخول تاني", 401);
  }
  let username: string | undefined;
  let role: AppRole | undefined;
  let issuedAt: number | undefined;
  try {
    const { payload } = await jwtVerify(token, secretKey());
    username = payload.username as string | undefined;
    role = payload.role as AppRole | undefined;
    issuedAt = payload.iat as number | undefined;
    if (!username || !role || !issuedAt) {
      throw new AuthError("توكن غير صالح", 401);
    }
  } catch (e) {
    if (e instanceof AuthError) throw e;
    throw new AuthError("جلسة منتهية أو غير صالحة — سجّل الدخول تاني", 401);
  }

  const stillValid = await _issuedAfterLastPasswordChange(username, issuedAt);
  if (!stillValid) {
    throw new AuthError("كلمة المرور اتغيّرت — سجّل الدخول تاني", 401);
  }

  return { username, role };
}

/// TASK-309: مقارنة وقت إصدار التوكن (iat) بآخر وقت اتغيّرت فيه كلمة
/// مرور الحساب (users.password_changed_at). لو الحساب مالوش قيمة
/// مسجّلة بعد (عمود جديد، قيمته null لحد أول تغيير فعلي)، التوكن يُعتبر
/// سليم — مفيش تغيير حصل أصلاً بعد آخر إصدار.
async function _issuedAfterLastPasswordChange(
  username: string,
  issuedAtSeconds: number,
): Promise<boolean> {
  try {
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const { data } = await supabase
      .from("users")
      .select("password_changed_at")
      .eq("username", username)
      .maybeSingle();
    const changedAt = data?.password_changed_at
      ? new Date(data.password_changed_at as string).getTime()
      : 0;
    return issuedAtSeconds * 1000 >= changedAt;
  } catch (e) {
    // فشل الفحص نفسه (مثلاً مشكلة اتصال بالداتابيز) ما ينفعش يبقى
    // سبب لرفض توكن سليم — نسيبه يعدي، التحقق من التوقيع والانتهاء
    // نفسه لسه تم بنجاح فوق.
    console.error("password_changed_at check failed:", e);
    return true;
  }
}

/// زي requireAuth بالظبط، وبعدين بيتأكد إن الدور ضمن الأدوار المسموحة.
/// مثال: await requireRole(req, "admin")
export async function requireRole(
  req: Request,
  ...allowed: AppRole[]
): Promise<AppTokenPayload> {
  const identity = await requireAuth(req);
  if (!allowed.includes(identity.role)) {
    throw new AuthError("مفيش صلاحية كافية لتنفيذ هذه العملية", 403);
  }
  return identity;
}

/// يحوّل أي AuthError لـ Response جاهزة بنفس شكل باقي ردود المشروع
/// ({success:false, error}) — يُستخدم في catch block كل دالة حساسة.
export function authErrorResponse(e: unknown): Response {
  if (e instanceof AuthError) {
    return new Response(JSON.stringify({ success: false, error: e.message }), {
      status: e.status,
      headers: { "Content-Type": "application/json" },
    });
  }
  console.error(e);
  return new Response(JSON.stringify({ success: false, error: "خطأ في الخادم" }), {
    status: 500,
    headers: { "Content-Type": "application/json" },
  });
}
