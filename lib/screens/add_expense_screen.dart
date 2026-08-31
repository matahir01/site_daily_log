import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/expense.dart';

class AddExpenseScreen extends StatefulWidget {
  final String siteId;
  final Expense? existingExpense; // pass to edit instead of create
  const AddExpenseScreen({super.key, required this.siteId, this.existingExpense});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  late final _amountController =
      TextEditingController(text: widget.existingExpense?.amount.toString());
  late final _noteController = TextEditingController(text: widget.existingExpense?.note);
  late ExpenseCategory _category = widget.existingExpense?.category ?? ExpenseCategory.materials;
  String? _receiptPath = widget.existingExpense?.receiptPhotoPath;
  bool _saving = false;

  bool get _isEditing => widget.existingExpense != null;

  String _label(ExpenseCategory c) {
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

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    setState(() => _saving = true);

    if (_isEditing) {
      final updated = Expense(
        id: widget.existingExpense!.id,
        siteId: widget.siteId,
        date: widget.existingExpense!.date, // keep original date
        category: _category,
        amount: amount,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        receiptPhotoPath: _receiptPath,
      );
      await DatabaseHelper.instance.updateExpense(updated);
    } else {
      final expense = Expense(
        id: const Uuid().v4(),
        siteId: widget.siteId,
        date: DateTime.now(),
        category: _category,
        amount: amount,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        receiptPhotoPath: _receiptPath,
      );
      await DatabaseHelper.instance.insertExpense(expense);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Expense' : 'New Expense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amountController,
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '\$ '),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ExpenseCategory>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: ExpenseCategory.values
                .map((c) => DropdownMenuItem(value: c, child: Text(_label(c))))
                .toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickReceipt,
            icon: const Icon(Icons.receipt_long),
            label: Text(_receiptPath == null ? 'Attach Receipt Photo' : 'Receipt Attached ✓'),
          ),
          if (_receiptPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_receiptPath!), height: 100),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator()
                : Text(_isEditing ? 'Update Expense' : 'Save Expense'),
          ),
        ],
      ),
    );
  }
}
