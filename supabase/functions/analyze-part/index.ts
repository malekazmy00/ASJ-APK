// supabase/functions/analyze-part/index.ts
//
// نقل حرفي لمنطق services/ai_service.py الأصلي: نفس البرومبت بالضبط،
// نفس سلسلة تصعيد النماذج (lite -> flash -> pro)، ونفس مفاتيح الـ JSON
// المتوقعة في الرد. الفرق الوحيد: بيشتغل كـ Edge Function عشان مفتاح
// Gemini يفضل سري على السيرفر، مش داخل تطبيق Flutter.
//
// ملاحظة لم تُختبر حياً بعد (زي حال real Gemini web search في النظام
// الأصلي) — لازم تجربة فعلية بعد النشر قبل الاعتماد عليها بالكامل.

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;

// نفس الترتيب المستخدم في settings.LITE_AI_MODEL / FAST_AI_MODEL / STRONG_AI_MODEL
// عدّل الأسماء هنا لو مختلفة عندك في core/config.py الأصلي.
const MODEL_CHAIN = [
  "gemini-2.0-flash-lite",
  "gemini-2.0-flash",
  "gemini-2.5-pro",
];

const PROMPT_TEMPLATE = (partNumber: string) => `أنت خبير فني متخصص في قطع غيار أجهزة التصوير الطبي (أشعة، رنين، أجهزة مختبرات).
المعلومة المتاحة لديك عن القطعة: '${partNumber}'
(ملحوظة: المعلومة دي ممكن تكون رقم قطعة بس، أو اسم/نص وصفي بس، أو الاتنين مع بعض موضحين بعلامة |)

لو مرفقة معك صورة، مطلوب منك تحدد شيئين منفصلين ومهمين بنفس القدر:

1) رقم القطعة (Part Number): هو الكود المطبوع أو المحفور على القطعة اللي بيمثل رقمها الرسمي عند الشركة المصنعة، وعادة بيكون قريب من كلمات زي P/N أو REF أو Art.Nr أو Teilenummer أو Part No. انتبه ولا تخلط بينه وبين أرقام تانية مطبوعة على نفس القطعة زي رقم الدفعة (Batch/Lot Number) أو تاريخ التصنيع أو الرقم التسلسلي (Serial Number) - دول مش رقم القطعة حتى لو ظاهرين بنفس الوضوح.
2) اسم/وصف القطعة: يعني إيه القطعة دي فعلياً (مثلاً "بوردة تغذية كهربائية"، "بورد تحكم رئيسي"، "أنبوبة أشعة") - ده منفصل تماماً عن الرقم، ومهم بنفس القدر.
3) اسم/موديل كودي للبوردة نفسها إن وجد (مثال: QX999) - أحياناً بيكون مطبوع على البوردة كود قصير مختلف تماماً عن رقم القطعة الطويل، ده بيمثل اسم موديل البوردة نفسها. لو لقيت كود من النوع ده، اذكره صراحة في حقل الملاحظات الفنية بصيغة واضحة زي "الاسم الكودي للبوردة: XXXX".

- لو المعلومة المتاحة لديك فيها الاتنين (رقم ونص) بالفعل، استخدمهم كما هم.
- لو معاك واحد بس منهم (رقم بس أو اسم بس) وكانت معاك صورة، حاول تقرأ التاني من الصورة نفسها.
- لو مقدرتش تقرأ التاني من الصورة، استخدم معرفتك الفعلية الحقيقية عن هذا النوع من القطع الطبية عشان تكمّل الناقص، بشرط تكون واثق فعلاً، ومتخترعش قيمة وهمية لو مش متأكد.
- لو مش متأكد من رقم القطعة نهائياً، وضح ده صراحة في الملاحظات بدل ما تخترع رقم عشوائي.

تعليمات "Compatible_Model": اسم جهاز طبي محدد وحقيقي (مثال: "Siemens Somatom Definition AS")، مش تصنيف عام. لو معرفتش جهاز محدد، قول ذلك صراحة في الملاحظات.

تعليمات "Market_Value": نطاق سعر تقديري حقيقي بالدولار، مش عبارات عامة. لو معرفتش رقم واقعي، قول كده صراحة.

اكتب ردك بالكامل بلغة عربية فصحى طبيعية وسليمة.

أرجع النتيجة كـ JSON بالمفاتيح التالية بالضبط:
- "Brand"
- "Category"
- "Part_Number"
- "Compatible_Model"
- "Additional_Compatibility"
- "Market_Value"
- "Gemini_Insights"

أرجع JSON فقط بدون أي نص إضافي.`;

Deno.serve(async (req) => {
  try {
    const { partNumberOrText, imageBase64 } = await req.json();
    if (!partNumberOrText) {
      return jsonResponse({ success: false, error: "بيانات ناقصة" }, 400);
    }

    const prompt = PROMPT_TEMPLATE(partNumberOrText);
    let lastError = "فشل بعد تجربة كل النماذج المتاحة";

    for (const model of MODEL_CHAIN) {
      try {
        const parts: unknown[] = [{ text: prompt }];
        if (imageBase64) {
          parts.push({
            inline_data: { mime_type: "image/jpeg", data: imageBase64 },
          });
        }

        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              contents: [{ parts }],
              generationConfig: {
                temperature: 0.1,
                topP: 0.95,
                topK: 40,
                maxOutputTokens: 1024,
              },
            }),
          },
        );

        if (res.status === 429) {
          lastError = "الباقة انتهت على هذا النموذج، جرّب نموذج أقوى";
          continue; // النموذج التالي في السلسلة
        }
        if (!res.ok) {
          lastError = `خطأ من Gemini: ${res.status}`;
          continue;
        }

        const data = await res.json();
        let text: string =
          data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
        text = text.replace(/```json\s*/g, "").replace(/```\s*/g, "").trim();

        const parsed = JSON.parse(text);
        return jsonResponse(
          {
            success: true,
            result: {
              Brand: parsed.Brand ?? "Unknown",
              Category: parsed.Category ?? "Unknown",
              Part_Number: parsed.Part_Number ?? partNumberOrText,
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
    return jsonResponse({ success: false, error: "خطأ في الخادم" }, 500);
  }
});

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
