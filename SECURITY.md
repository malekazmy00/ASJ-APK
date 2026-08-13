# مصفوفة الأمان — ASJ Medical Systems Store

مرجع واحد لمين المفروض يقدر يعمل إيه، وعلى أي مستوى بيتفرض ده فعلياً
(Backend حقيقي، أو واجهة بس). أي Edge Function أو RPC أو شاشة جديدة
لازم تتحقق من الجدول ده أولاً قبل ما تتنفذ، عشان نضمن كل حاجة بتتفرض
في نفس الطبقة بدل ما كل جزء من المشروع يطبّق نسخته الخاصة.

**التاريخ**: أغسطس ٢٠٢٦، بعد مراجعة الأمان (Sprint 1-3) + TASK-401.

## نموذج الثقة العام
المشروع **بدون Supabase Auth وRLS** (قرار معماري متعمد). بدل RLS، عندنا
طبقتين:
1. **JWT مخصص** (`APP_JWT_SECRET`) — بيثبت الهوية (`username` + `role`).
   أي Edge Function حساسة بتتحقق منه عبر `requireAuth`/`requireRole`
   (`supabase/functions/_shared/auth.ts`).
2. **صلاحيات فردية** (`can_export`, `can_track`, `can_edit` في جدول
   `users`) — بتتفحص إما في الـ Edge Function نفسها (زي `export-data`)
   أو في الواجهة بس لحد دلوقتي (راجع عمود "الإنفاذ" تحت).

## المصفوفة

| العملية | Worker | Engineer | Admin | الإنفاذ الفعلي |
|---|---|---|---|---|
| عرض المخزون | ✓ | ✓ | ✓ | مفتوح (anon، بدون RLS — قرار متعمد) |
| تسجيل قطعة جديدة | ✓ | ✓ | ✓ | **Backend** — Edge Function `create-inventory-item` (`requireAuth`) + RPC مقفولة على anon (TASK-401) |
| صرف قطعة | ✓ | ✓ | ✓ | **Backend** — `dispatch-item` (`requireAuth`) + RPC ذرية مقفولة على anon |
| استرجاع قطعة | ✓ | ✓ | ✓ | **Backend** — `return-item` (`requireAuth`) + RPC ذرية مقفولة على anon |
| تعديل بيانات أساسية (موقع/حالة/ملكية) | حسب `can_edit` | ✓ | ✓ | **Backend** — `update-item-fields` (`requireAuth` + فحص `can_edit`/admin فعلي من جدول `users`، مش بس شرط واجهة) |
| تعديل رقم القطعة/السريال | حسب `can_edit` | ✓ | ✓ | **Backend** — يعدّي على `pending_approvals` + موافقة أدمن عبر `resolve-approval` (`requireRole('admin')`) |
| أرشفة (بدل حذف نهائي) | — | حسب الشاشة | ✓ | **Backend** — `archive-item` (`requireAuth` + فحص `can_edit`/admin فعلي) + RPC ذرية مقفولة على anon |
| إنشاء مستخدم | ✗ | ✗ | ✓ | **Backend** — `admin-create-user` (`requireRole('admin')`) |
| إعادة تعيين كلمة مرور (لمستخدم تاني) | ✗ | ✗ | ✓ | **Backend** — `admin-reset-password` (`requireRole('admin')`) |
| تغيير كلمة المرور الشخصية | ✓ | ✓ | ✓ | **Backend** — `change-password` (`requireAuth`، الهوية من التوكن مش من الـ body) |
| تصدير بيانات | حسب `can_export` | حسب `can_export` | ✓ | **Backend** — `export-data` (`requireAuth` + فحص `can_export`/admin من جدول `users`) |
| تحليل قطعة بالذكاء الاصطناعي | ✓ | ✓ | ✓ | **Backend** — `analyze-part`/`search-part` (`requireAuth` + rate limit لكل مستخدم) |
| فتح/إغلاق جلسة دخول | ✓ | ✓ | ✓ | **Backend** — `open-session` (`requireAuth`، username من التوكن) |
| الموافقة/الرفض على طلب معلّق | ✗ | ✗ | ✓ | **Backend** — `resolve-approval` (`requireRole('admin')`) |

## معروف وناقص
لا يوجد حالياً — كل عمليات الكتابة الحساسة على `inventory_items`/
`users`/`transactions_log`/`pending_approvals` بقت خلف Edge Function
متحقق منها + RPC ذرية مقفولة على anon/authenticated. أي عملية كتابة
جديدة تتبع نفس القاعدة تحت.

## حماية Race Condition على مستوى الحالة (State Transitions)
مراجعة إضافية (أغسطس ٢٠٢٦) لقت إن كل RPCs التحويل (dispatch/return/
archive/update-fields) كانت بتعمل UPDATE من غير شرط على الحالة
الحالية — يعني لو جلستان نفذوا نفس العملية في نفس اللحظة (Race)، كل
واحدة كانت بتنجح لوحدها بصمت. اتصلح بإضافة الشرط **جوه نفس جملة
UPDATE نفسها** (مش SELECT منفصل قبلها)، فمهما حصل تسابق صف واحد بس
هو اللي يعدّي:

| العملية | الحالة المطلوبة قبل التنفيذ | لو مش متحققة |
|---|---|---|
| Dispatch | القطعة مش `Out` أصلاً | خطأ عمل واضح (409) |
| Return | القطعة `Out` فعلاً | خطأ عمل واضح (409) |
| Archive | القطعة مش `Archived` أصلاً | خطأ عمل واضح (409) |
| تعديل بيانات أساسية | القطعة مش `Archived` | خطأ عمل واضح (409) |
| حسم طلب موافقة | الطلب لسه `Pending` | خطأ عمل واضح (409) |

راجع `migrations/016_state_transition_guards.sql` — كل استثناء من
النوع ده بيتحدد بـ prefix `BUSINESS_ERROR:` والـ Edge Function
بترجّعه للعميل كـ 409 برسالة عربية واضحة (`_shared/errors.ts`)، مش
500/400 عام.

**`exitType` بقى محكوم بـ whitelist** في `dispatch-item` (Sale/Loan/
Damaged بس) بدل أي نص حر.

## تشديد إضافي (017) — بدون أي تغيير في السلوك الحالي
- `dispatch_item_tx`: بقت كمان بترفض صرف قطعة متأرشفة (دفاعي بحت —
  مفيش شاشة أصلاً بتعرض قطعة متأرشفة للاختيار).
- `update_item_basic_fields_tx`: `p_status` بقى محكوم بـ whitelist
  (Available/Out/Reserved/Damaged — نفس خيارات الدروب-داون بالظبط).
- `create-inventory-item`: whitelist لـ `entryType`/`ownershipStatus`/
  `condition` (كلهم دروب-داون ثابت) + حدود طول للحقول النصية. `itemType`
  عمداً من غير whitelist (بيقبل نص حر لاسم معدة الشغل يدوياً) — بس بحد طول.

## قرار عمل مفتوح (مش باگ — يحتاج قرارك)
هل الصرف مسموح بس من حالة "متاح"، ولا من أي حالة غير "صادر" (السلوك
الحالي — بيسمح بصرف قطعة "محجوزة" أو "تالفة" كمان)؟ لو الأول، لازم
تعديل شرط `dispatch_item_tx` من `status <> 'Out'` لـ `status =
'Available'` — ده هيغيّر سلوك موجود فعلياً (منع صرف المحجوز/التالف)،
فمتعملش من غير تأكيد صريح.

## القاعدة للمستقبل
أي عملية كتابة جديدة على `inventory_items` أو `transactions_log` أو
`users` لازم تتبع نفس النمط:
```
Flutter → Edge Function (requireAuth/requireRole) → service_role client → RPC/Transaction → Database
```
مفيش RPC أو جدول يتاح لـ `anon`/`authenticated` مباشرة إلا لو كانت
عملية قراءة بحتة (زي `get_grouped_inventory`) بنفس مستوى الحساسية
اللي أصلاً القراءة المباشرة للجدول متاحة بيه.
