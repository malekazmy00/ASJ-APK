// supabase/functions/analyze-part/index.ts
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;

const MODEL_CHAIN = [
  "gemini-2.0-flash-lite",
  "gemini-2.0-flash",
  "gemini-2.5-pro",
];

const PROMPT_TEMPLATE = (partNumber: string) => `أنت خبير فني متخصص في قطع غيار أجهزة التصوير الطبي (أشعة، رنين، أجهزة مختبرات).
المعلومة المتاحة لديك عن القطعة: '${partNumber}'
(ملحوظة: المعلومة دي ممكن تكون رقم قطعة بس، أو اسم/نص وصفي بس، أو الاتنين مع بعض موضحين بعلامة |)

لو مرفقة معك صورة، مطلوب منك تحدد العناصر التالية بدقة وبشكل منفصل تماماً عن بعض:

1) رقم القطعة (Part Number): الكود المطبوع أو المحفور اللي بيمثل رقمها الرسمي عند الشركة المصنعة، غالباً قريب من كلمات زي P/N أو REF أو Art.Nr أو Part No.
2) الرقم التسلسلي (Serial Number): كود مختلف تماماً عن رقم القطعة، عادة قريب من كلمة S/N أو Serial، وبيكون فريد لكل قطعة فردية. لو لقيت رقم زي كده، حطه في Serial_Number منفصل تماماً - لا تخلطه أبداً مع Part_Number.
3) اسم/وصف القطعة: يعني إيه القطعة دي فعلياً (مثلاً "بوردة تغذية كهربائية").
4) لا تخلط أي من الاتنين فوق مع رقم الدفعة (Batch/Lot Number) أو تاريخ التصنيع.

- لو المعلومة المتاحة لديك فيها الاتنين (رقم ونص) بالفعل، استخدمهم كما هم.
- لو معاك واحد بس منهم وكانت معاك صورة، حاول تقرأ التاني من الصورة نفسها.
- لو مقدرتش تقرأ رقم القطعة أو الرقم التسلسلي نهائياً، سيب الحقل فاضياً ووضح ده في الملاحظات.

تعليمات "Compatible_Model": اسم جهاز طبي محدد وحقيقي، مش تصنيف عام.
تعليمات "Market_Value": نطاق سعر تقديري حقيقي بالدولار.

اكتب ردك بالكامل بلغة عربية فصحى طبيعية وسليمة.

أرجع النتيجة كـ JSON بالمفاتيح التالية بالضبط:
- "Brand"
- "Category"
- "Part_Number"
- "Serial_Number"
- "Compatible_Model"
- "Additional_Compatibility"
- "Market_Value"
- "Gemini_Insights"

أرجع JSON فقط بدون أي نص إضافي.`;

Deno.serve(async (req) => {
  try {
    const { partNumberOrText, imageBase64 } = await req.json();

    if (!partNumberOrText && !imageBase64) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const effectiveText = partNumberOrText || "غير معروف - يرجى التعرف على القطعة من الصورة مباشرة";
    const prompt = PROMPT_TEMPLATE(effectiveText);
    let lastError = "فشل بعد تجربة كل النماذج المتاحة";

    for (const model of MODEL_CHAIN) {
      try {
        const parts: unknown[] = [{ text: prompt }];
        if (imageBase64) {
          parts.push({ inline_data: { mime_type: "image/jpeg", data: imageBase64 } });
        }

        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              contents: [{ parts }],
              generationConfig: { temperature: 0.1, topP: 0.95, topK: 40, maxOutputTokens: 1024 },
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
              Brand: parsed.Brand ?? "Unknown",
              Category: parsed.Category ?? "Unknown",
              Part_Number: parsed.Part_Number ?? effectiveText,
              Serial_Number: parsed.Serial_Number ?? "",
              Compatible_Model: parsed.Compatible_Model ?? "",
              Additional_Compatibility: parsed.Additional_Compatibility ?? "",
              Market_Value: parsed.Market_Value ?? "",
              Gemini_Insights: parsed.Gemini_Insights ?? "تم الفحص بنجاح",
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