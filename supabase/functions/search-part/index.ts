// supabase/functions/search-part/index.ts
// بحث Gemini حي عن قطعة (رقم أو نص وصفي) — بيشتغل بالتوازي مع البحث
// الداخلي (المخزون + قاعدة المعرفة + استعلامات سابقة)، مش بديل عنه.
// النتيجتين لازم يتعرضوا مع بعض دايماً في الشاشة، مفيش تسلسل بينهم.
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;

const MODEL_CHAIN = [
  "gemini-2.0-flash-lite",
  "gemini-2.0-flash",
  "gemini-2.5-pro",
];

const PROMPT_TEMPLATE = (query: string) => `أنت خبير فني متخصص في قطع غيار أجهزة التصوير الطبي (أشعة، رنين، أجهزة مختبرات).
مطلوب منك تبحث بمعلوماتك العامة عن القطعة دي وتديني أفضل تخمين ممكن، حتى لو المعلومة مش مؤكدة 100%:
'${query}'

اكتب ردك بالكامل بلغة عربية فصحى طبيعية وسليمة.

أرجع النتيجة كـ JSON بالمفاتيح التالية بالضبط:
- "Brand"
- "Category"
- "Compatible_Model"
- "Market_Value" (نطاق سعر تقديري بالدولار)
- "Summary" (وصف مختصر في سطرين بحد أقصى، بسيط وموجّه للمستخدم مباشرة، من غير أي تفاصيل تقنية عن كيفية توليد الإجابة)
- "Confidence" (High أو Medium أو Low، حسب مدى ثقتك في المعلومة)

أرجع JSON فقط بدون أي نص إضافي.`;

Deno.serve(async (req) => {
  try {
    const { query } = await req.json();

    if (!query || String(query).trim() === "") {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const prompt = PROMPT_TEMPLATE(query);
    let lastError = "فشل بعد تجربة كل النماذج المتاحة";

    for (const model of MODEL_CHAIN) {
      try {
        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              contents: [{ parts: [{ text: prompt }] }],
              generationConfig: { temperature: 0.2, topP: 0.95, topK: 40, maxOutputTokens: 512 },
            }),
          },
        );

        if (res.status === 429) {
          lastError = "الباقة انتهت على هذا النموذج، جرّب نموذج أقوى";
          continue;
        }
        if (!res.ok) {
          lastError = `خطأ من Gemini: ${res.status} - ${await res.text()}`;
          continue;
        }

        const data = await res.json();
        let text: string = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
        text = text.replace(/```json\s*/g, "").replace(/```\s*/g, "").trim();

        const parsed = JSON.parse(text);
        return jsonResponse(
          {
            success: true,
            result: {
              Brand: parsed.Brand ?? "",
              Category: parsed.Category ?? "",
              Compatible_Model: parsed.Compatible_Model ?? "",
              Market_Value: parsed.Market_Value ?? "",
              Summary: parsed.Summary ?? "",
              Confidence: parsed.Confidence ?? "Low",
            },
          },
          200,
        );
      } catch (innerError) {
        console.error(`Model ${model} failed:`, innerError);
        lastError = String(innerError);
        continue;
      }
    }

    return jsonResponse({ success: false, error: lastError }, 502);
  } catch (e) {
    console.error(e);
    return jsonResponse({ success: false, error: `خطأ في الخادم: ${e}` }, 500);
  }
});

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}