enum ExpenseCategory { materials, labor, equipment, other }

class Expense {
  final String id;
  final String siteId;
  final DateTime date;
  final ExpenseCategory category;
  final double amount;
  final String? note;
  final String? receiptPhotoPath;

  Expense({
    required this.id,
    required this.siteId,
    required this.date,
    required this.category,
    required this.amount,
    this.note,
    this.receiptPhotoPath,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'siteId': siteId,
        'date': date.toIso8601String(),
        'category': category.name,
        'amount': amount,
        'note': note,
        'receiptPhotoPath': receiptPhotoPath,
      };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'],
        siteId: map['siteId'],
        date: DateTime.parse(map['date']),
        category: ExpenseCategory.values.firstWhere((e) => e.name == map['category']),
        amount: (map['amount'] as num).toDouble(),
        note: map['note'],
        receiptPhotoPath: map['receiptPhotoPath'],
      );
}
