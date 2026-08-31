import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';

class PdfReportService {
  static String _categoryLabel(ExpenseCategory c) {
    switch (c) {
      case ExpenseCategory.materials:
        return 'Materials';
      case ExpenseCategory.labor:
        return 'Labor';
      case ExpenseCategory.equipment:
        return 'Equipment';
      case ExpenseCategory.other:
        return 'Other';
    }
  }

  /// Generates a PDF report for a single site: daily logs + expenses + totals.
  /// Returns the saved file path.
  static Future<File> generateSiteReport({
    required Project project,
    required Site site,
    required List<DailyLog> logs,
    required List<Expense> expenses,
  }) async {
    final doc = pw.Document();
    final dateFmt = DateFormat.yMMMd();
    final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header(project.name, site.name, site.address),
          pw.SizedBox(height: 20),
          pw.Text('Daily Logs', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          if (logs.isEmpty) pw.Text('No daily logs recorded.'),
          ...logs.map((log) => _logBlock(log, dateFmt)),
          pw.SizedBox(height: 20),
          pw.Text('Expenses', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          if (expenses.isEmpty) pw.Text('No expenses recorded.'),
          if (expenses.isNotEmpty) _expenseTable(expenses, dateFmt),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total: \$${total.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return _saveDoc(doc, '${site.name}_report');
  }

  /// Generates a PDF report for an entire project: all sites, all logs, all expenses.
  static Future<File> generateProjectReport({
    required Project project,
    required List<Site> sites,
    required Map<String, List<DailyLog>> logsBySite,
    required Map<String, List<Expense>> expensesBySite,
  }) async {
    final doc = pw.Document();
    final dateFmt = DateFormat.yMMMd();

    double projectTotal = 0;
    for (final e in expensesBySite.values.expand((x) => x)) {
      projectTotal += e.amount;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _header(project.name, project.client ?? 'Project Report', null),
          pw.SizedBox(height: 8),
          pw.Text(
            'Total Project Expenses: \$${projectTotal.toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          for (final site in sites) ...[
            pw.Text(site.name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (site.address != null) pw.Text(site.address!, style: const pw.TextStyle(fontSize: 10)),
            pw.Divider(),
            pw.Text('Daily Logs', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ...(logsBySite[site.id] ?? []).map((log) => _logBlock(log, dateFmt)),
            pw.SizedBox(height: 8),
            pw.Text('Expenses', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            if ((expensesBySite[site.id] ?? []).isNotEmpty)
              _expenseTable(expensesBySite[site.id]!, dateFmt)
            else
              pw.Text('No expenses recorded.'),
            pw.SizedBox(height: 20),
          ],
        ],
      ),
    );

    return _saveDoc(doc, '${project.name}_full_report');
  }

  static pw.Widget _header(String title, String subtitle, String? extra) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 14)),
        if (extra != null) pw.Text(extra, style: const pw.TextStyle(fontSize: 10)),
        pw.Text('Generated: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      ],
    );
  }

  static pw.Widget _logBlock(DailyLog log, DateFormat dateFmt) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(dateFmt.format(log.date), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          if (log.weather != null) pw.Text('Weather: ${log.weather}'),
          if (log.crewCount != null) pw.Text('Crew: ${log.crewCount}'),
          if (log.workCompleted != null) pw.Text('Work completed: ${log.workCompleted}'),
          if (log.issues != null) pw.Text('Issues: ${log.issues}'),
          if (log.photoPaths.isNotEmpty)
            pw.Wrap(
              spacing: 6,
              runSpacing: 6,
              children: log.photoPaths.map((path) {
                final file = File(path);
                if (!file.existsSync()) return pw.SizedBox();
                return pw.Image(pw.MemoryImage(file.readAsBytesSync()), width: 100, height: 100, fit: pw.BoxFit.cover);
              }).toList(),
            ),
        ],
      ),
    );
  }

  static pw.Widget _expenseTable(List<Expense> expenses, DateFormat dateFmt) {
    return pw.TableHelper.fromTextArray(
      headers: ['Date', 'Category', 'Amount', 'Note'],
      data: expenses
          .map((e) => [
                dateFmt.format(e.date),
                _categoryLabel(e.category),
                '\$${e.amount.toStringAsFixed(2)}',
                e.note ?? '',
              ])
          .toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  static Future<File> _saveDoc(pw.Document doc, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(p.join(dir.path, 'reports'));
    await reportsDir.create(recursive: true);
    final safeName = baseName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(reportsDir.path, '${safeName}_$timestamp.pdf'));
    await file.writeAsBytes(await doc.save());
    return file;
  }
}
