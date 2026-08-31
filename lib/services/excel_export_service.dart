import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';

/// Generates .xlsx workbooks as a spreadsheet-friendly alternative to the
/// PDF reports — handy for importing into Excel/Sheets for further
/// analysis, cost tracking, or client submission.
class ExcelExportService {
  static final _dateFmt = DateFormat.yMMMd();

  /// Builds a full project workbook: one "Daily Logs" sheet, one
  /// "Materials & Equipment" sheet, and one "Expenses" sheet, each with a
  /// Site column so everything can be filtered/pivoted per site.
  static Future<File> generateProjectWorkbook({
    required Project project,
    required List<Site> sites,
    required Map<String, List<DailyLog>> logsBySite,
    required Map<String, List<MaterialItem>> materialsBySite,
    required Map<String, List<Expense>> expensesBySite,
  }) async {
    final excel = Excel.createExcel();
    final siteNameById = {for (final s in sites) s.id: s.name};

    _buildLogsSheet(excel, sites, logsBySite, siteNameById, includeSiteColumn: true);
    _buildMaterialsSheet(excel, sites, materialsBySite, siteNameById, includeSiteColumn: true);
    _buildExpensesSheet(excel, sites, expensesBySite, siteNameById, includeSiteColumn: true);

    // The `excel` package always creates a default "Sheet1" — drop it once
    // our real sheets exist so the workbook opens on useful data.
    if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
      excel.delete('Sheet1');
    }

    return _save(excel, '${project.name}_export');
  }

  /// Builds a single-site workbook (Daily Logs / Materials & Equipment /
  /// Expenses), mirroring [PdfReportService.generateSiteReport].
  static Future<File> generateSiteWorkbook({
    required Project project,
    required Site site,
    required List<DailyLog> logs,
    required List<MaterialItem> materials,
    required List<Expense> expenses,
  }) async {
    final excel = Excel.createExcel();
    final siteNameById = {site.id: site.name};

    _buildLogsSheet(excel, [site], {site.id: logs}, siteNameById, includeSiteColumn: false);
    _buildMaterialsSheet(excel, [site], {site.id: materials}, siteNameById, includeSiteColumn: false);
    _buildExpensesSheet(excel, [site], {site.id: expenses}, siteNameById, includeSiteColumn: false);

    if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
      excel.delete('Sheet1');
    }

    return _save(excel, '${site.name}_export');
  }

  static void _buildLogsSheet(
    Excel excel,
    List<Site> sites,
    Map<String, List<DailyLog>> logsBySite,
    Map<String, String> siteNameById, {
    required bool includeSiteColumn,
  }) {
    final sheet = excel['Daily Logs'];
    final headers = [
      if (includeSiteColumn) 'Site',
      'Date',
      'Weather',
      'Crew Count',
      'Work Completed',
      'Issues / Delays',
      'Latitude',
      'Longitude',
      'Photos',
      'Synced',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final site in sites) {
      final logs = logsBySite[site.id] ?? [];
      for (final log in logs) {
        sheet.appendRow([
          if (includeSiteColumn) TextCellValue(siteNameById[site.id] ?? site.id),
          TextCellValue(_dateFmt.format(log.date)),
          TextCellValue(log.weather ?? ''),
          if (log.crewCount != null) IntCellValue(log.crewCount!) else TextCellValue(''),
          TextCellValue(log.workCompleted ?? ''),
          TextCellValue(log.issues ?? ''),
          if (log.latitude != null) DoubleCellValue(log.latitude!) else TextCellValue(''),
          if (log.longitude != null) DoubleCellValue(log.longitude!) else TextCellValue(''),
          IntCellValue(log.photoPaths.length),
          TextCellValue(log.isSynced ? 'Synced' : 'Pending Sync'),
        ]);
      }
    }
    _autoWidth(sheet, headers.length);
  }

  static void _buildMaterialsSheet(
    Excel excel,
    List<Site> sites,
    Map<String, List<MaterialItem>> materialsBySite,
    Map<String, String> siteNameById, {
    required bool includeSiteColumn,
  }) {
    final sheet = excel['Materials & Equipment'];
    final headers = [
      if (includeSiteColumn) 'Site',
      'Item',
      'Quantity',
      'Unit',
      'Category',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final site in sites) {
      final items = materialsBySite[site.id] ?? [];
      for (final item in items) {
        sheet.appendRow([
          if (includeSiteColumn) TextCellValue(siteNameById[site.id] ?? site.id),
          TextCellValue(item.itemName),
          DoubleCellValue(item.quantity),
          TextCellValue(item.unit ?? ''),
          TextCellValue(item.category.label),
        ]);
      }
    }
    _autoWidth(sheet, headers.length);
  }

  static void _buildExpensesSheet(
    Excel excel,
    List<Site> sites,
    Map<String, List<Expense>> expensesBySite,
    Map<String, String> siteNameById, {
    required bool includeSiteColumn,
  }) {
    final sheet = excel['Expenses'];
    final headers = [
      if (includeSiteColumn) 'Site',
      'Date',
      'Category',
      'Amount',
      'Note',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    double total = 0;
    for (final site in sites) {
      final expenses = expensesBySite[site.id] ?? [];
      for (final e in expenses) {
        total += e.amount;
        sheet.appendRow([
          if (includeSiteColumn) TextCellValue(siteNameById[site.id] ?? site.id),
          TextCellValue(_dateFmt.format(e.date)),
          TextCellValue(_categoryLabel(e.category)),
          DoubleCellValue(e.amount),
          TextCellValue(e.note ?? ''),
        ]);
      }
    }
    sheet.appendRow([]);
    final totalRow = [
      if (includeSiteColumn) TextCellValue(''),
      TextCellValue(''),
      TextCellValue('Total'),
      DoubleCellValue(total),
      TextCellValue(''),
    ];
    sheet.appendRow(totalRow);
    _autoWidth(sheet, headers.length);
  }

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

  static void _autoWidth(Sheet sheet, int columnCount) {
    for (var i = 0; i < columnCount; i++) {
      sheet.setColumnWidth(i, 22);
    }
  }

  static Future<File> _save(Excel excel, String baseName) async {
    final dir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(p.join(dir.path, 'reports'));
    await reportsDir.create(recursive: true);
    final safeName = baseName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(reportsDir.path, '${safeName}_$timestamp.xlsx'));
    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Failed to encode the Excel workbook.');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
