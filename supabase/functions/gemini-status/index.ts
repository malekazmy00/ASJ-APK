// supabase/functions/gemini-status/index.ts
// فحص بسيط لصحة الاتصال بـ Gemini — بيفحص كل مفتاح مضبوط (GEMINI_API_KEY،
// GEMINI_API_KEY_2، GEMINI_API_KEY_3) على حدة بأخف نموذج وأقل prompt
// ممكن، ويرجّع حالة كل مفتاح على حدة + ملخص عام.
const GEMINI_KEY_NAMES = ["GEMINI_API_KEY", "GEMINI_API_KEY_2", "GEMINI_API_KEY_3"];

Deno.serve(async (_req) => {
  const keys = GEMINI_KEY_NAMES
    .map((name) => ({ name, value: Deno.env.get(name) }))
    .filter((k) => !!k.value && k.value.trim() !== "");

  if (keys.length === 0) {
    return jsonResponse(
      { success: false, error: "لا يوجد أي مفتاح Gemini مضبوط على السيرفر", keys: [] },
      200,
    );
  }

  const results = await Promise.all(
    keys.map(async (k) => {
      try {
        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent?key=${k.value}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              contents: [{ parts: [{ text: "رد بكلمة واحدة: تمام" }] }],
              generationConfig: { maxOutputTokens: 10 },
            }),
          },
        );
        return { name: k.name, ok: res.ok, status: res.status };
      } catch (e) {
        return { name: k.name, ok: false, status: null, error: String(e) };
      }
    }),
  );

  const anyOk = results.some((r) => r.ok);
  return jsonResponse({ success: anyOk, keys: results }, 200);
});

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}