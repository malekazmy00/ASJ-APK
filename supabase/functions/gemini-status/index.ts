// supabase/functions/gemini-status/index.ts
// فحص بسيط لصحة الاتصال بـ Gemini — بينادي أخف نموذج بأقل prompt
// ممكن ويرجّع نجاح/فشل بس، مش تحليل فعلي.
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;

Deno.serve(async (_req) => {
  try {
    if (!GEMINI_API_KEY) {
      return jsonResponse({ success: false, error: "GEMINI_API_KEY غير مضبوط على السيرفر" }, 500);
    }

    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: "رد بكلمة واحدة: تمام" }] }],
          generationConfig: { maxOutputTokens: 10 },
        }),
      },
    );

    if (!res.ok) {
      return jsonResponse(
        { success: false, error: `فشل الاتصال: ${res.status}` },
        200,
      );
    }

    return jsonResponse({ success: true }, 200);
  } catch (e) {
    console.error(e);
    return jsonResponse({ success: false, error: String(e) }, 200);
  }
});

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}