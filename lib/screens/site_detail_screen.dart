import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/site.dart';
import '../models/project.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../services/pdf_report_service.dart';
import '../services/excel_export_service.dart';
import '../models/material_item.dart';
import 'add_daily_log_screen.dart';
import 'add_expense_screen.dart';
import '../widgets/quick_expense_sheet.dart';
import '../widgets/quick_log_sheet.dart';

class SiteDetailScreen extends StatefulWidget {
  final Site site;
  final Project project;
  const SiteDetailScreen({super.key, required this.site, required this.project});

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen> {
  final _db = DatabaseHelper.instance;
  List<DailyLog> _logs = [];
  List<Expense> _expenses = [];
  List<MaterialItem> _materials = [];
  bool _generatingPdf = false;
  bool _generatingExcel = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await _db.getLogsForSite(widget.site.id);
    final expenses = await _db.getExpensesForSite(widget.site.id);
    final materials = await _db.getMaterialsForSite(widget.site.id);
    setState(() {
      _logs = logs;
      _expenses = expenses;
      _materials = materials;
    });
  }

  String _categoryLabel(ExpenseCategory c) {
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

  Future<void> _confirmDelete(String title, VoidCallback onConfirmed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $title?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirmed();
  }

  Future<void> _exportPdf() async {
    setState(() => _generatingPdf = true);
    try {
      final file = await PdfReportService.generateSiteReport(
        project: widget.project,
        site: widget.site,
        logs: _logs,
        expenses: _expenses,
      );
      if (mounted) {
        await Share.shareXFiles([XFile(file.path)], text: '${widget.site.name} report');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _generatingExcel = true);
    try {
      final file = await ExcelExportService.generateSiteWorkbook(
        project: widget.project,
        site: widget.site,
        logs: _logs,
        materials: _materials,
        expenses: _expenses,
      );
      if (mounted) {
        await Share.shareXFiles([XFile(file.path)], text: '${widget.site.name} export');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate Excel file: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.site.name),
          actions: [
            IconButton(
              icon: _generatingPdf
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf),
              tooltip: 'Export site report',
              onPressed: _generatingPdf ? null : _exportPdf,
            ),
            IconButton(
              icon: _generatingExcel
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.table_chart),
              tooltip: 'Export site report (.xlsx)',
              onPressed: _generatingExcel ? null : _exportExcel,
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Daily Logs', icon: Icon(Icons.description)),
            Tab(text: 'Expenses', icon: Icon(Icons.attach_money)),
          ]),
        ),
        body: TabBarView(
          children: [
            // Daily logs tab
            _logs.isEmpty
                ? const Center(child: Text('No daily logs yet.'))
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (ctx, i) {
                      final log = _logs[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          title: Row(
                            children: [
                              Text(DateFormat.yMMMd().format(log.date)),
                              const SizedBox(width: 8),
                              _SyncBadge(isSynced: log.isSynced),
                            ],
                          ),
                          subtitle: Text(
                            [
                              if (log.weather != null) 'Weather: ${log.weather}',
                              if (log.crewCount != null) 'Crew: ${log.crewCount}',
                              if (log.workCompleted != null) log.workCompleted!,
                            ].join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (log.photoPaths.isNotEmpty)
                                Icon(Icons.photo, color: Colors.grey[600], size: 18),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _confirmDelete('this log', () async {
                                  await _db.deleteDailyLog(log.id);
                                  _load();
                                }),
                              ),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddDailyLogScreen(siteId: widget.site.id, existingLog: log),
                              ),
                            );
                            _load();
                          },
                        ),
                      );
                    },
                  ),
            // Expenses tab
            _expenses.isEmpty
                ? const Center(child: Text('No expenses yet.'))
                : ListView.builder(
                    itemCount: _expenses.length,
                    itemBuilder: (ctx, i) {
                      final e = _expenses[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text(_categoryLabel(e.category)[0])),
                        title: Text('\$${e.amount.toStringAsFixed(2)} — ${_categoryLabel(e.category)}'),
                        subtitle: Text(
                          '${DateFormat.yMMMd().format(e.date)}${e.note != null ? ' • ${e.note}' : ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete('this expense', () async {
                            await _db.deleteExpense(e.id);
                            _load();
                          }),
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddExpenseScreen(siteId: widget.site.id, existingExpense: e),
                            ),
                          );
                          _load();
                        },
                      );
                    },
                  ),
          ],
        ),
        floatingActionButton: Builder(
          builder: (ctx) {
            return GestureDetector(
              onLongPress: () async {
                final currentTab = DefaultTabController.of(ctx).index;
                if (currentTab == 0) {
                  await Navigator.push(ctx, MaterialPageRoute(builder: (_) => AddDailyLogScreen(siteId: widget.site.id)));
                } else {
                  await Navigator.push(ctx, MaterialPageRoute(builder: (_) => AddExpenseScreen(siteId: widget.site.id)));
                }
                _load();
              },
              child: FloatingActionButton.extended(
                // Tap = quick add (default, fastest path). Long-press = full form
                // with more fields, for anyone who wants to enter more detail.
                onPressed: () async {
                  final currentTab = DefaultTabController.of(ctx).index;
                  final saved = await showModalBottomSheet<bool>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => currentTab == 0
                        ? QuickLogSheet(siteId: widget.site.id)
                        : QuickExpenseSheet(siteId: widget.site.id),
                  );
                  if (saved == true) _load();
                },
                icon: const Icon(Icons.flash_on),
                label: const Text('Quick Add'),
                tooltip: 'Long-press for the full form with more fields',
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Small "Synced" / "Pending Sync" chip shown on each daily log, reflecting
/// whether it was included in the most recent Google Drive backup.
class _SyncBadge extends StatelessWidget {
  final bool isSynced;
  const _SyncBadge({required this.isSynced});

  @override
  Widget build(BuildContext context) {
    final color = isSynced ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isSynced ? Icons.cloud_done : Icons.cloud_off, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            isSynced ? 'Synced' : 'Pending Sync',
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
