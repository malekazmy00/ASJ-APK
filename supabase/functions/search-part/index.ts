// supabase/functions/search-part/index.ts
// بحث Gemini حي عن قطعة (رقم أو نص وصفي) — بيشتغل بالتوازي مع البحث
// الداخلي (المخزون + قاعدة المعرفة + استعلامات سابقة)، مش بديل عنه.
// النتيجتين لازم يتعرضوا مع بعض دايماً في الشاشة، مفيش تسلسل بينهم.
//
// يدعم أكتر من مفتاح Gemini (GEMINI_API_KEY, GEMINI_API_KEY_2,
// GEMINI_API_KEY_3 - كلهم اختياريين عدا الأول).
const GEMINI_KEYS = ["GEMINI_API_KEY", "GEMINI_API_KEY_2", "GEMINI_API_KEY_3"]
  .map((name) => Deno.env.get(name))
  .filter((v): v is string => !!v && v.trim() !== "");

const MODEL_CHAIN = [
  "gemini-3.5-flash-lite",
  "gemini-3.6-flash",
  "gemini-3.1-pro-preview",
];

const PROMPT_TEMPLATE = (query: string) => `أنت خبير فني متخصص في قطع غيار أجهزة التصوير الطبي (أشعة، رنين، أجهزة مختبرات).
استخدم أفضل معرفتك العامة عن القطعة دي، وديني أفضل إجابة ممكنة، حتى لو
المعلومة مش مؤكدة 100%:
'${query}'

اكتب ردك بالكامل بلغة عربية فصحى طبيعية وسليمة. الجهاز المتوافق
(Compatible_Model) لازم يكون اسم موديل جهاز طبي حقيقي ومحدد، مش تصنيف عام.

أرجع النتيجة كـ JSON بالمفاتيح التالية بالضبط:
- "Brand"
- "Category"
- "Part_Model" (الاسم الكودي/موديل القطعة نفسها لو معروف، مختلف عن الجهاز المتوافق)
- "Compatible_Model"
- "Market_Value" (نطاق سعر تقديري بالدولار)
- "Summary" (وصف مختصر في سطرين بحد أقصى، بسيط وموجّه للمستخدم مباشرة، من غير أي تفاصيل تقنية عن كيفية توليد الإجابة)
- "Confidence" (High أو Medium أو Low، حسب مدى ثقتك في المعلومة)

أرجع JSON فقط بدون أي نص إضافي (حتى لو استخدمت أداة البحث، ما تحطش أي مصادر أو روابط في الرد، JSON نظيف بس).`;

Deno.serve(async (req) => {
  try {
    if (GEMINI_KEYS.length === 0) {
      return jsonResponse({ success: false, error: "لا يوجد أي مفتاح Gemini مضبوط على السيرفر" }, 500);
    }

    const { query } = await req.json();

    if (!query || String(query).trim() === "") {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const prompt = PROMPT_TEMPLATE(query);
    let lastError = "فشل بعد تجربة كل النماذج والمفاتيح المتاحة";

    for (const model of MODEL_CHAIN) {
      for (const apiKey of GEMINI_KEYS) {
        try {
          const res = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
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
            const bodyText = await res.text();
            lastError = `فشل على ${model} (429): ${bodyText}`;
            continue;
          }
          if (!res.ok) {
            lastError = `خطأ من Gemini: ${res.status} - ${await res.text()}`;
            continue;
          }

          const data = await res.json();
          let text: string = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
          text = text.replace(/```json\s*/g, "").replace(/```\s*/g, "").trim();
          const firstBrace = text.indexOf("{");
          const lastBrace = text.lastIndexOf("}");
          if (firstBrace !== -1 && lastBrace !== -1) {
            text = text.substring(firstBrace, lastBrace + 1);
          }

          const parsed = JSON.parse(text);
          return jsonResponse(
            {
              success: true,
              result: {
                Brand: parsed.Brand ?? "",
                Category: parsed.Category ?? "",
                Part_Model: parsed.Part_Model ?? "",
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