import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/expense.dart';

/// Fast-path expense entry: amount + category chip + optional receipt photo.
/// Designed for one-handed, gloved-thumb use on a job site.
class QuickExpenseSheet extends StatefulWidget {
  final String siteId;
  const QuickExpenseSheet({super.key, required this.siteId});

  // Remembers the last category used this app session, so the most likely
  // choice is already selected when the sheet opens.
  static ExpenseCategory _lastCategory = ExpenseCategory.materials;

  @override
  State<QuickExpenseSheet> createState() => _QuickExpenseSheetState();
}

class _QuickExpenseSheetState extends State<QuickExpenseSheet> {
  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();
  late ExpenseCategory _category = QuickExpenseSheet._lastCategory;
  String? _receiptPath;
  bool _saving = false;

  static const _categories = [
    (ExpenseCategory.materials, 'Materials', Icons.hardware),
    (ExpenseCategory.labor, 'Labor', Icons.engineering),
    (ExpenseCategory.equipment, 'Equipment', Icons.construction),
    (ExpenseCategory.other, 'Other', Icons.receipt_long),
  ];

  @override
  void initState() {
    super.initState();
    // Auto-focus the amount field with the numeric keypad ready — the very
    // first thing that happens is the user can start typing a number.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_amountFocus);
    });
  }

  Future<void> _snapReceipt() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (file == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${const Uuid().v4()}${p.extension(file.path)}';
    final savedPath = p.join(appDir.path, 'receipts', fileName);
    await Directory(p.join(appDir.path, 'receipts')).create(recursive: true);
    await File(file.path).copy(savedPath);
    setState(() => _receiptPath = savedPath);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount first')),
      );
      return;
    }

    setState(() => _saving = true);
    QuickExpenseSheet._lastCategory = _category;

    final expense = Expense(
      id: const Uuid().v4(),
      siteId: widget.siteId,
      date: DateTime.now(),
      category: _category,
      amount: amount,
      note: null,
      receiptPhotoPath: _receiptPath,
    );
    await DatabaseHelper.instance.insertExpense(expense);

    HapticFeedback.lightImpact();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Quick Expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            focusNode: _amountFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              prefixText: '\$ ',
              prefixStyle: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _categories.map((c) {
              final (cat, label, icon) = c;
              final selected = _category == cat;
              return ChoiceChip(
                label: Text(label),
                avatar: Icon(icon, size: 18),
                selected: selected,
                onSelected: (_) => setState(() => _category = cat),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _snapReceipt,
                  icon: Icon(_receiptPath == null ? Icons.camera_alt : Icons.check_circle),
                  label: Text(_receiptPath == null ? 'Snap Receipt' : 'Receipt Added'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
