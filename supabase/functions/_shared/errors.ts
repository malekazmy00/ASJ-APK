// supabase/functions/_shared/errors.ts
//
// الدوال في _shared/auth.ts بتتعامل مع أخطاء الهوية/الصلاحية
// (401/403). الملف ده بيتعامل مع فئة تانية: أخطاء "منطق العمل"
// (Business Rules) الجايه من RPC — زي محاولة صرف قطعة اتصرفت خلاص،
// أو استرجاع قطعة مش صادرة أصلاً، أو حسم طلب موافقة اتحسم قبل كده.
//
// الـ RPCs دي بترمي استثناء نصه مبدوء بـ 'BUSINESS_ERROR:' (راجع
// migrations/016_state_transition_guards.sql) — الدالة دي بتلقطه
// وترجع 409 (Conflict) برسالة عربية نضيفة، بدل ما يوصل كـ 400/500 عام
// زي أي خطأ تقني تاني.

export function rpcErrorResponse(error: { message: string }): Response {
  const marker = "BUSINESS_ERROR:";
  const idx = error.message.indexOf(marker);
  if (idx !== -1) {
    const clean = error.message.slice(idx + marker.length).trim();
    return new Response(
      JSON.stringify({ success: false, error: clean, businessError: true }),
      { status: 409, headers: { "Content-Type": "application/json" } },
    );
  }
  return new Response(JSON.stringify({ success: false, error: error.message }), {
    status: 400,
    headers: { "Content-Type": "application/json" },
  });
}
