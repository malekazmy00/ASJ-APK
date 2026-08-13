// supabase/functions/_shared/validation.ts
//
// تحقق إدخال بسيط ومقصود بسيط كده — مش مكتبة validation كاملة.
// الهدف: رفض قيم غريبة/طويلة جداً قبل ما توصل لقاعدة البيانات، مش
// فرض قواعد عمل معقدة (دي مكانها الطبيعي في الـ RPC نفسها لو احتجناها).

export class ValidationError extends Error {}

/// لو value موجودة، لازم تكون واحدة من allowed. undefined/null مقبولين
/// (يعني الحقل اختياري) إلا لو required=true.
export function requireOneOf(
  value: unknown,
  allowed: string[],
  fieldName: string,
  { required = false }: { required?: boolean } = {},
): void {
  if (value === undefined || value === null || value === "") {
    if (required) throw new ValidationError(`${fieldName} مطلوب`);
    return;
  }
  if (typeof value !== "string" || !allowed.includes(value)) {
    throw new ValidationError(`قيمة غير معروفة لحقل ${fieldName}`);
  }
}

/// لو value موجودة (نص)، طولها لازم يكون أقل من أو يساوي max.
export function requireMaxLength(value: unknown, max: number, fieldName: string): void {
  if (typeof value === "string" && value.length > max) {
    throw new ValidationError(`${fieldName} طويل جداً (الحد الأقصى ${max} حرف)`);
  }
}
