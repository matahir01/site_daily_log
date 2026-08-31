import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/daily_log.dart';
import '../models/expense.dart';
import '../models/material_item.dart';
import '../services/pdf_report_service.dart';
import '../services/excel_export_service.dart';
import '../services/google_drive_service.dart';
import 'site_detail_screen.dart';

class ProjectDashboardScreen extends StatefulWidget {
  final Project project;
  const ProjectDashboardScreen({super.key, required this.project});

  @override
  State<ProjectDashboardScreen> createState() => _ProjectDashboardScreenState();
}

class _ProjectDashboardScreenState extends State<ProjectDashboardScreen> {
  final _db = DatabaseHelper.instance;
  final _drive = GoogleDriveService.instance;

  List<Site> _sites = [];
  double _totalExpenses = 0;
  int _pendingSyncCount = 0;
  int _totalLogCount = 0;
  bool _generatingPdf = false;
  bool _generatingExcel = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sites = await _db.getSitesForProject(widget.project.id);
    final total = await _db.getTotalExpensesForProject(widget.project.id);
    final pending = await _db.getPendingSyncCount();
    final totalLogs = await _db.getTotalLogCount();
    setState(() {
      _sites = sites;
      _totalExpenses = total;
      _pendingSyncCount = pending;
      _totalLogCount = totalLogs;
    });
  }

  Future<void> _addSite() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Site'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Site name'), autofocus: true),
            TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Address (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final site = Site(
        id: const Uuid().v4(),
        projectId: widget.project.id,
        name: nameController.text.trim(),
        address: addressController.text.trim().isEmpty ? null : addressController.text.trim(),
        createdAt: DateTime.now(),
      );
      await _db.insertSite(site);
      _load();
    }
  }

  Future<void> _confirmDeleteSite(Site site) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${site.name}"?'),
        content: const Text('This deletes the site and all its logs and expenses. This cannot be undone.'),
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
    if (confirmed == true) {
      await _db.deleteSite(site.id);
      _load();
    }
  }

  Future<void> _exportProjectPdf() async {
    setState(() => _generatingPdf = true);
    try {
      final logsBySite = <String, List<DailyLog>>{};
      final expensesBySite = <String, List<Expense>>{};
      for (final site in _sites) {
        logsBySite[site.id] = await _db.getLogsForSite(site.id);
        expensesBySite[site.id] = await _db.getExpensesForSite(site.id);
      }
      final file = await PdfReportService.generateProjectReport(
        project: widget.project,
        sites: _sites,
        logsBySite: logsBySite,
        expensesBySite: expensesBySite,
      );
      if (mounted) {
        await Share.shareXFiles([XFile(file.path)], text: '${widget.project.name} full report');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _exportProjectExcel() async {
    setState(() => _generatingExcel = true);
    try {
      final logsBySite = <String, List<DailyLog>>{};
      final materialsBySite = <String, List<MaterialItem>>{};
      final expensesBySite = <String, List<Expense>>{};
      for (final site in _sites) {
        logsBySite[site.id] = await _db.getLogsForSite(site.id);
        materialsBySite[site.id] = await _db.getMaterialsForSite(site.id);
        expensesBySite[site.id] = await _db.getExpensesForSite(site.id);
      }
      final file = await ExcelExportService.generateProjectWorkbook(
        project: widget.project,
        sites: _sites,
        logsBySite: logsBySite,
        materialsBySite: materialsBySite,
        expensesBySite: expensesBySite,
      );
      if (mounted) {
        await Share.shareXFiles([XFile(file.path)], text: '${widget.project.name} full export');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate Excel file: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingExcel = false);
    }
  }

  Future<void> _backupToDrive() async {
    setState(() => _syncing = true);
    try {
      await _drive.backup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backed up to Google Drive as ${_drive.userEmail ?? 'your account'}.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _restoreFromDrive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Google Drive?'),
        content: const Text(
          'This replaces all local projects, sites, logs, materials, and expenses with the most recent Drive backup. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _syncing = true);
    try {
      await _drive.restore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore complete. Reopen the project to see restored data.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showBackupMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Back up now'),
              subtitle: const Text('Uploads the local database to your Google Drive App Data folder'),
              onTap: () => Navigator.pop(ctx, 'backup'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Restore from Drive'),
              subtitle: const Text('Replaces local data with your most recent Drive backup'),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'backup') await _backupToDrive();
    if (choice == 'restore') await _restoreFromDrive();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        actions: [
          IconButton(
            icon: _syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_sync),
            tooltip: 'Google Drive backup / restore',
            onPressed: _syncing ? null : _showBackupMenu,
          ),
          IconButton(
            icon: _generatingExcel
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_chart),
            tooltip: 'Export full project report (.xlsx)',
            onPressed: (_generatingExcel || _sites.isEmpty) ? null : _exportProjectExcel,
          ),
          IconButton(
            icon: _generatingPdf
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf),
            tooltip: 'Export full project report (.pdf)',
            onPressed: (_generatingPdf || _sites.isEmpty) ? null : _exportProjectPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Project Expenses', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('\$${_totalExpenses.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (_totalLogCount > 0) ...[
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _pendingSyncCount == 0 ? Icons.cloud_done : Icons.cloud_off,
                              size: 16,
                              color: _pendingSyncCount == 0 ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _pendingSyncCount == 0
                                  ? 'All logs synced'
                                  : '$_pendingSyncCount of $_totalLogCount logs pending sync',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: _syncing ? null : _backupToDrive,
                          icon: const Icon(Icons.cloud_upload, size: 16),
                          label: const Text('Back up'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: _sites.isEmpty
                ? const Center(child: Text('No sites yet. Tap + to add one.'))
                : ListView.builder(
                    itemCount: _sites.length,
                    itemBuilder: (ctx, i) {
                      final s = _sites[i];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.location_on)),
                        title: Text(s.name),
                        subtitle: s.address != null ? Text(s.address!) : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDeleteSite(s),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SiteDetailScreen(site: s, project: widget.project)),
                        ).then((_) => _load()),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSite,
        child: const Icon(Icons.add),
      ),
    );
  }
}
