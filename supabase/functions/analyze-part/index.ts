// supabase/functions/analyze-part/index.ts
//
// يدعم أكتر من مفتاح Gemini (GEMINI_API_KEY, GEMINI_API_KEY_2,
// GEMINI_API_KEY_3 - كلهم اختياريين عدا الأول). بيجرب كل نموذج مع كل
// مفتاح بالترتيب قبل ما يصعّد للنموذج الأقوى اللي بعده، عشان لو مفتاح
// واحد خلصت حصته أو فيه مشكلة فيه، الباقي يكمل الشغل من غيره.
const GEMINI_KEYS = ["GEMINI_API_KEY", "GEMINI_API_KEY_2", "GEMINI_API_KEY_3"]
  .map((name) => Deno.env.get(name))
  .filter((v): v is string => !!v && v.trim() !== "");

const MODEL_CHAIN = [
  "gemini-3.5-flash-lite",
  "gemini-3.6-flash",
  "gemini-3.1-pro-preview",
];

const PROMPT_TEMPLATE = (partNumber: string) => `أنت خبير فني متخصص في قطع غيار أجهزة التصوير الطبي (أشعة، رنين، أجهزة مختبرات).
المعلومة المتاحة لديك عن القطعة: '${partNumber}'
(ملحوظة: المعلومة دي ممكن تكون رقم قطعة بس، أو اسم/نص وصفي بس، أو الاتنين مع بعض موضحين بعلامة |)

استخدم أفضل معرفتك العامة للتأكد من رقم القطعة ده. الجهاز المتوافق
(Compatible_Model) لازم يكون اسم موديل جهاز طبي حقيقي ومحدد (مثلاً "GE
BrightSpeed" أو "Siemens Somatom Definition") مش تصنيف عام زي "جهاز أشعة
مقطعية".

لو مرفقة معك صورة، مطلوب منك تحدد العناصر التالية بدقة وبشكل منفصل تماماً عن بعض:

1) رقم القطعة (Part Number): الكود المطبوع أو المحفور اللي بيمثل رقمها الرسمي عند الشركة المصنعة، غالباً قريب من كلمات زي P/N أو REF أو Art.Nr أو Part No.
2) الموديل/الاسم الكودي (Part_Model): كود أو اسم تاني للقطعة نفسها (مش الجهاز اللي بتركب فيه) — بعض القطع بتتعرف بيه بجانب رقم القطعة، لو موجود اكتبه.
3) الرقم التسلسلي (Serial Number): كود مختلف تماماً عن رقم القطعة، عادة قريب من كلمة S/N أو Serial، وبيكون فريد لكل قطعة فردية. لو لقيت رقم زي كده، حطه في Serial_Number منفصل تماماً - لا تخلطه أبداً مع Part_Number. الرقم التسلسلي ميجيش من البحث خالص، من الصورة بس لو موجود عليها.
4) اسم/وصف القطعة: يعني إيه القطعة دي فعلياً (مثلاً "بوردة تغذية كهربائية").
5) لا تخلط أي من الاتنين فوق مع رقم الدفعة (Batch/Lot Number) أو تاريخ التصنيع.

- لو المعلومة المتاحة لديك فيها الاتنين (رقم ونص) بالفعل، استخدمهم كما هم.
- لو معاك واحد بس منهم وكانت معاك صورة، حاول تقرأ التاني من الصورة نفسها.
- لو مقدرتش تقرأ رقم القطعة أو الرقم التسلسلي نهائياً، سيب الحقل فاضياً ووضح ده في الملاحظات.

تعليمات "Market_Value": نطاق سعر تقديري حقيقي بالدولار.

اكتب ردك بالكامل بلغة عربية فصحى طبيعية وسليمة.

أرجع النتيجة كـ JSON بالمفاتيح التالية بالضبط:
- "Brand"
- "Category"
- "Part_Number"
- "Part_Model"
- "Serial_Number"
- "Compatible_Model"
- "Additional_Compatibility"
- "Market_Value"
- "Gemini_Insights"

أرجع JSON فقط بدون أي نص إضافي (حتى لو استخدمت أداة البحث، ما تحطش أي مصادر أو روابط في الرد، JSON نظيف بس).`;

Deno.serve(async (req) => {
  try {
    if (GEMINI_KEYS.length === 0) {
      return jsonResponse({ success: false, error: "لا يوجد أي مفتاح Gemini مضبوط على السيرفر" }, 500);
    }

    const { partNumberOrText, imageBase64 } = await req.json();

    if (!partNumberOrText && !imageBase64) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const effectiveText = partNumberOrText || "غير معروف - يرجى التعرف على القطعة من الصورة مباشرة";
    const prompt = PROMPT_TEMPLATE(effectiveText);
    let lastError = "فشل بعد تجربة كل النماذج والمفاتيح المتاحة";

    for (const model of MODEL_CHAIN) {
      for (const apiKey of GEMINI_KEYS) {
        try {
          const parts: unknown[] = [{ text: prompt }];
          if (imageBase64) {
            parts.push({ inline_data: { mime_type: "image/jpeg", data: imageBase64 } });
          }

          const res = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
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
            // بنسجل نص الخطأ الفعلي من Gemini بدل رسالة عامة، عشان لو
            // السبب حاجة تانية غير استهلاك حصة حقيقي (مفتاح غير مفعّل،
            // نموذج يحتاج فوترة...) نشوفه بالظبط بدل التخمين.
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
          // لو أداة البحث ضافت أي نص قبل/بعد الـ JSON، ناخد أول { لحد آخر }
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
                Brand: parsed.Brand ?? "Unknown",
                Category: parsed.Category ?? "Unknown",
                Part_Number: parsed.Part_Number ?? effectiveText,
                Part_Model: parsed.Part_Model ?? "",
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