// supabase/functions/search-part/index.ts
// بحث Gemini حي عن قطعة (رقم أو نص وصفي) — بيشتغل بالتوازي مع البحث
// الداخلي (المخزون + قاعدة المعرفة + استعلامات سابقة)، مش بديل عنه.
// النتيجتين لازم يتعرضوا مع بعض دايماً في الشاشة، مفيش تسلسل بينهم.
//
// الجولة الثالثة (نقطة ٤) — تحسين جودة البحث، ٣ مراحل:
//   Stage A: استخلاص مرن (brand/code/model_name/keyword) من النص الخام
//            بموديل سريع (flash-lite)، يتحمّل أي ترتيب/أخطاء إملائية.
//   Stage B: بحث محلي فوري في specs_knowledge_base بالنتيجة المستخلصة —
//            لو فيه تطابق، نرجعه على طول من غير أي استدعاء AI تاني.
//   Stage C: لو مفيش تطابق محلي، استعلام منظم (مش نص حر) + system
//            instruction تقفل النموذج على مجال أجهزة التصوير الطبي، بدل
//            ما يرجع معلومات عامة مالهاش علاقة.
//
// يدعم أكتر من مفتاح Gemini (GEMINI_API_KEY, GEMINI_API_KEY_2,
// GEMINI_API_KEY_3 - كلهم اختياريين عدا الأول).

import { createClient } from "npm:@supabase/supabase-js@2";

const GEMINI_KEYS = ["GEMINI_API_KEY", "GEMINI_API_KEY_2", "GEMINI_API_KEY_3"]
  .map((name) => Deno.env.get(name))
  .filter((v): v is string => !!v && v.trim() !== "");

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const EXTRACTION_MODEL = "gemini-3.5-flash-lite";
const MAIN_MODEL_CHAIN = [
  "gemini-3.5-flash-lite",
  "gemini-3.6-flash",
  "gemini-3.1-pro-preview",
];

interface Extraction {
  brand: string;
  code: string;
  model_name: string;
  keyword: string;
}

const EXTRACTION_PROMPT = (raw: string) => `استخرج من النص التالي (ممكن يكون بأي ترتيب للكلمات أو فيه أخطاء إملائية) بيانات قطعة غيار جهاز تصوير طبي.

النص: '${raw}'

أرجع JSON بالمفاتيح دي بالظبط، وسيب أي مفتاح فاضي "" لو مش موجود في النص:
- "brand": اسم الشركة المصنعة لو موجود، صحّح أي خطأ إملائي واضح (مثلاً "seimens" -> "Siemens")
- "code": رقم أو كود القطعة لو موجود (أرقام أو حروف+أرقام)
- "model_name": اسم موديل الجهاز الطبي لو موجود (مثلاً Avanto, Aera)
- "keyword": أي كلمة وصفية عن نوع القطعة لو موجودة (مثلاً "بورد"، "board"، "كابل")

أرجع JSON فقط بدون أي نص إضافي.`;

const SYSTEM_INSTRUCTION = `أنت مساعد فني متخصص حصرياً في قطع غيار أجهزة التصوير الطبي (أشعة، رنين، مختبرات) — ماركات زي Siemens وGE وPhilips وToshiba/Canon وHitachi وغيرها.
فسّر أي كود أو اسم مكتوب في سياق قطعة غيار طبية أولاً ودايماً، حتى لو الكود عام أو ممكن يشبه حاجة تانية (اسم أغنية، منتج استهلاكي، شركة من قطاع مختلف). ممنوع تخرج عن السياق ده خالص.
لو مفيش معلومة مؤكدة عن الكود/الاسم ده تحديداً في مجال الأجهزة الطبية، قول صراحة في حقل Confidence القيمة "None" وسيب باقي الحقول فاضية — ممنوع ترجع معلومات عامة أو تخمينية مالهاش علاقة أكيدة بالمجال.`;

const PROMPT_TEMPLATE = (structuredQuery: string) => `استخدم أفضل معرفتك الفنية عن القطعة دي:
${structuredQuery}

اكتب ردك بالكامل بلغة عربية فصحى طبيعية وسليمة. الجهاز المتوافق
(Compatible_Model) لازم يكون اسم موديل جهاز طبي حقيقي ومحدد، مش تصنيف عام.

أرجع النتيجة كـ JSON بالمفاتيح التالية بالضبط:
- "Brand"
- "Category"
- "Part_Model" (الاسم الكودي/موديل القطعة نفسها لو معروف، مختلف عن الجهاز المتوافق)
- "Compatible_Model"
- "Market_Value" (نطاق سعر تقديري بالدولار)
- "Summary" (وصف مختصر في سطرين بحد أقصى، بسيط وموجّه للمستخدم مباشرة)
- "Confidence" (High أو Medium أو Low أو None، حسب مدى ثقتك — استخدم None لو مفيش تطابق مؤكد في مجال الأجهزة الطبية)

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
    const rawQuery = String(query).trim();

    // === Stage A: استخلاص مرن (تجربة، مش حرجة — لو فشلت نكمل بالنص الخام) ===
    const extraction = await tryExtract(rawQuery);

    // === Stage B: بحث محلي فوري في قاعدة المعرفة بتاعتنا ===
    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const localMatch = await tryLocalMatch(supabase, extraction, rawQuery);
    if (localMatch) {
      return jsonResponse({ success: true, result: localMatch }, 200);
    }

    // === Stage C: استعلام منظم + سياق مقفول على المجال ===
    const structuredQuery = buildStructuredQuery(extraction, rawQuery);
    const result = await runMainSearch(structuredQuery);
    if (result) {
      return jsonResponse({ success: true, result }, 200);
    }

    return jsonResponse({ success: false, error: "فشل بعد تجربة كل النماذج والمفاتيح المتاحة" }, 502);
  } catch (e) {
    console.error(e);
    return jsonResponse({ success: false, error: `خطأ في الخادم: ${e}` }, 500);
  }
});

/// Stage A — استدعاء خفيف وسريع لاستخلاص برَاند/كود/موديل/كلمة وصفية من
/// النص الخام. أي فشل هنا (شبكة/quota/JSON غير صالح) بيرجّع استخلاص
/// فاضي، فالمنطق بعده بيرجع تلقائياً للنص الخام كامل (Stage C fallback).
async function tryExtract(raw: string): Promise<Extraction> {
  const empty: Extraction = { brand: "", code: "", model_name: "", keyword: "" };
  for (const apiKey of GEMINI_KEYS) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${EXTRACTION_MODEL}:generateContent?key=${apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: EXTRACTION_PROMPT(raw) }] }],
            generationConfig: { temperature: 0, maxOutputTokens: 200 },
          }),
        },
      );
      if (!res.ok) continue;
      const data = await res.json();
      let text: string = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
      text = extractJsonBlock(text);
      const parsed = JSON.parse(text);
      return {
        brand: String(parsed.brand ?? "").trim(),
        code: String(parsed.code ?? "").trim(),
        model_name: String(parsed.model_name ?? "").trim(),
        keyword: String(parsed.keyword ?? "").trim(),
      };
    } catch (e) {
      console.error("Stage A extraction failed:", e);
      continue;
    }
  }
  return empty;
}

/// Stage B — تطابق شكي (fuzzy) في specs_knowledge_base بالكود أو
/// الموديل أو البراند المستخلصين. لو الاستخلاص فاضي بالكامل، بيجرب
/// النص الخام نفسه كـ fallback بسيط.
// deno-lint-ignore no-explicit-any
async function tryLocalMatch(supabase: any, extraction: Extraction, rawQuery: string) {
  const candidates = [extraction.code, extraction.model_name, rawQuery].filter((v) => v && v.trim() !== "");
  for (const term of candidates) {
    const { data } = await supabase
      .from("specs_knowledge_base")
      .select("*")
      .or(`Part_Number.ilike.%${term}%,Part_Model.ilike.%${term}%`)
      .limit(1);
    if (data && data.length > 0) {
      const row = data[0];
      return {
        Brand: row.Brand ?? "",
        Category: row.Category ?? "",
        Part_Model: row.Part_Model ?? "",
        Compatible_Model: row.Compatible_Model ?? "",
        Market_Value: row.Market_Value ?? "",
        Summary: `موجودة في قاعدة المعرفة الداخلية بتاعتنا (رقم القطعة: ${row.Part_Number}).`,
        Confidence: "High",
        Source: "local",
      };
    }
  }
  return null;
}

/// يبني نص استعلام منظم من نتيجة الاستخلاص بدل ما نبعت النص الخام
/// زي ما هو — لو الاستخلاص فاضي بالكامل (فشل Stage A)، بيرجع للنص
/// الخام كامل.
function buildStructuredQuery(extraction: Extraction, rawQuery: string): string {
  const parts: string[] = [];
  if (extraction.brand) parts.push(`البراند: ${extraction.brand}`);
  if (extraction.code) parts.push(`الكود/رقم القطعة: ${extraction.code}`);
  if (extraction.model_name) parts.push(`اسم موديل الجهاز: ${extraction.model_name}`);
  if (extraction.keyword) parts.push(`الوصف: ${extraction.keyword}`);
  return parts.length > 0 ? parts.join("، ") : rawQuery;
}

/// Stage C — الاستدعاء الرئيسي بسياق مقفول (system_instruction) على
/// استعلام منظم بدل نص حر.
async function runMainSearch(structuredQuery: string) {
  const prompt = PROMPT_TEMPLATE(structuredQuery);
  for (const model of MAIN_MODEL_CHAIN) {
    for (const apiKey of GEMINI_KEYS) {
      try {
        const res = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              system_instruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
              contents: [{ parts: [{ text: prompt }] }],
              generationConfig: { temperature: 0.2, topP: 0.95, topK: 40, maxOutputTokens: 512 },
            }),
          },
        );

        if (res.status === 429) {
          console.error(`Model ${model} rate-limited (429)`);
          continue;
        }
        if (!res.ok) {
          console.error(`Gemini error on ${model}: ${res.status} - ${await res.text()}`);
          continue;
        }

        const data = await res.json();
        let text: string = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
        text = extractJsonBlock(text);
        const parsed = JSON.parse(text);
        return {
          Brand: parsed.Brand ?? "",
          Category: parsed.Category ?? "",
          Part_Model: parsed.Part_Model ?? "",
          Compatible_Model: parsed.Compatible_Model ?? "",
          Market_Value: parsed.Market_Value ?? "",
          Summary: parsed.Summary ?? "",
          Confidence: parsed.Confidence ?? "None",
          Source: "gemini",
        };
      } catch (innerError) {
        console.error(`Model ${model} failed:`, innerError);
        continue;
      }
    }
  }
  return null;
}

function extractJsonBlock(text: string): string {
  text = text.replace(/```json\s*/g, "").replace(/```\s*/g, "").trim();
  const firstBrace = text.indexOf("{");
  const lastBrace = text.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace !== -1) {
    text = text.substring(firstBrace, lastBrace + 1);
  }
  return text;
}

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}