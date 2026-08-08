import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/knowledge_base_entry.dart';

/// يطابق repositories/knowledge_repo.py، بما في ذلك منطق create_or_update
/// الأصلي: لو رقم القطعة معروف بالفعل، أي بيانات AI جديدة تروح لملاحظة
/// إضافية بدل الكتابة فوق الحقول الموثوقة (Brand/Compatible_Model).
class KnowledgeBaseRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<KnowledgeBaseEntry?> getByPartNumber(String partNumber) async {
    final rows = await _client
        .from('specs_knowledge_base')
        .select()
        .eq('Part_Number', partNumber)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return KnowledgeBaseEntry.fromMap(list.first);
  }

  Future<List<KnowledgeBaseEntry>> searchByCategoryOrPart(String query) async {
    final rows = await _client
        .from('specs_knowledge_base')
        .select()
        .or('Part_Number.ilike.%$query%,Category.ilike.%$query%,Brand.ilike.%$query%')
        .limit(50);
    return (rows as List).map((r) => KnowledgeBaseEntry.fromMap(r)).toList();
  }

  /// نفس منطق create_or_update الأصلي بالضبط:
  /// - غير موجود: يكتب Part_Number + Gemini_Insights بس، الباقي فاضي
  ///   لحد ما يتملى يدوياً من شاشة التعديل.
  /// - موجود: مايكتبش فوق Brand/Compatible_Model الموثوقين، يضيف أي
  ///   بيانات جديدة كملاحظة فقط (مطلوب دمجها يدوياً بمعرفة المستخدم).
  Future<void> createOrAppendInsight({
    required String partNumber,
    required String geminiInsights,
  }) async {
    final existing = await getByPartNumber(partNumber);

    if (existing == null) {
      await _client.from('specs_knowledge_base').insert({
        'Part_Number': partNumber,
        'Gemini_Insights': geminiInsights,
      });
      return;
    }

    final prev = existing.geminiInsights ?? '';
    if (geminiInsights.isEmpty || prev.contains(geminiInsights)) return;
    final combined = prev.isEmpty ? geminiInsights : '$prev\n---\n$geminiInsights';
    await updateFields(partNumber, {'Gemini_Insights': combined});
  }

  Future<void> updateFields(String partNumber, Map<String, dynamic> fields) async {
    fields['last_updated'] = DateTime.now().toIso8601String();
    await _client
        .from('specs_knowledge_base')
        .update(fields)
        .eq('Part_Number', partNumber);
  }

  /// إنشاء أو تحديث — تُستخدم من شاشة تعديل القطعة لحفظ حقول قاعدة
  /// المعرفة المرتبطة برقم القطعة مباشرة، حتى لو السجل مش موجود بعد.
  Future<void> upsertFields(String partNumber, Map<String, dynamic> fields) async {
    final existing = await getByPartNumber(partNumber);
    if (existing == null) {
      await _client.from('specs_knowledge_base').insert({
        'Part_Number': partNumber,
        ...fields,
      });
    } else {
      await updateFields(partNumber, fields);
    }
  }

  /// يكتب الموديل (الاسم الكودي) بس لو لسه مش متسجّل، بنفس فلسفة حماية
  /// البيانات الموثوقة من الكتابة فوقها تلقائياً من AI (زي Brand
  /// وCompatible_Model بالظبط).
  Future<void> setPartModelIfEmpty(String partNumber, String partModel) async {
    if (partModel.trim().isEmpty) return;
    final existing = await getByPartNumber(partNumber);
    if (existing == null) {
      await _client.from('specs_knowledge_base').insert({
        'Part_Number': partNumber,
        'Part_Model': partModel.trim(),
      });
    } else if (existing.partModel == null || existing.partModel!.trim().isEmpty) {
      await updateFields(partNumber, {'Part_Model': partModel.trim()});
    }
  }

  /// استيراد جماعي من CSV (شاشة الأدمن) — upsert على دفعات من 500 صف،
  /// بيستبدل بيانات رقم القطعة بالكامل لو موجود (عكس createOrAppendInsight
  /// اللي بتحمي البيانات الموثوقة من الكتابة فوقها تلقائياً من AI؛ هنا
  /// الأدمن نفسه اللي بيستورد البيانات بقرار واعي، فمفيش داعي للحماية).
  Future<int> bulkUpsert(List<Map<String, dynamic>> rows) async {
    const batchSize = 500;
    var imported = 0;
    for (var i = 0; i < rows.length; i += batchSize) {
      final batch = rows.sublist(i, i + batchSize > rows.length ? rows.length : i + batchSize);
      await _client.from('specs_knowledge_base').upsert(batch, onConflict: 'Part_Number');
      imported += batch.length;
    }
    return imported;
  }
}