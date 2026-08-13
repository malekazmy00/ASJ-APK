// supabase/functions/_shared/rate_limit.ts
//
// TASK-319: تحديد معدّل استخدام الـ AI endpoints لكل مستخدم — قبل كده
// analyze-part وsearch-part كانوا مفتوحين تماماً (مفيش حتى تحقق هوية)،
// يعني أي حد معاه الـ anon key يقدر يستهلك حصة Gemini من غير أي حد أو
// حتى معرفة مين اللي استهلكها. دلوقتي كل نداء لازم يبقى معاه توكن
// صالح (identity.username)، وبيتسجل في ai_request_log عشان نقدر نحسب
// معدل الاستخدام لكل مستخدم لوحده.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export interface RateLimitOptions {
  perMinute: number;
  perDay: number;
}

export interface RateLimitResult {
  allowed: boolean;
  error?: string;
}

export async function checkRateLimit(
  supabase: SupabaseClient,
  username: string,
  endpoint: string,
  opts: RateLimitOptions,
): Promise<RateLimitResult> {
  const now = Date.now();
  const oneMinuteAgo = new Date(now - 60_000).toISOString();
  const oneDayAgo = new Date(now - 24 * 60 * 60_000).toISOString();

  const { count: minuteCount } = await supabase
    .from("ai_request_log")
    .select("id", { count: "exact", head: true })
    .eq("username", username)
    .eq("endpoint", endpoint)
    .gte("created_at", oneMinuteAgo);

  if ((minuteCount ?? 0) >= opts.perMinute) {
    return {
      allowed: false,
      error: `تجاوزت الحد المسموح (${opts.perMinute} طلب/دقيقة) لهذه الخدمة — استنى شوية وحاول تاني`,
    };
  }

  const { count: dayCount } = await supabase
    .from("ai_request_log")
    .select("id", { count: "exact", head: true })
    .eq("username", username)
    .eq("endpoint", endpoint)
    .gte("created_at", oneDayAgo);

  if ((dayCount ?? 0) >= opts.perDay) {
    return {
      allowed: false,
      error: `تجاوزت الحد اليومي المسموح (${opts.perDay} طلب/يوم) لهذه الخدمة`,
    };
  }

  // بنسجل المحاولة قبل ما نكمل تنفيذ الطلب نفسه — حتى لو الطلب فشل
  // بعد كده (مثلاً Gemini رجّع 429)، هو لسه استهلك نداء فعلي وقتّه.
  await supabase.from("ai_request_log").insert({ username, endpoint });
  return { allowed: true };
}
