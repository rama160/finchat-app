class TransactionModel {
  final int? id;
  final String chatId;
  final String transactionDate;
  final String transactionTime;
  final String type;
  final String category;
  final String description;
  final double amount;
  final String paymentMethod;
  final String merchant;
  final String notes;
  final String source;
  final int isSynced;

  TransactionModel({
    this.id,
    this.chatId = 'local_user',
    required this.transactionDate,
    required this.transactionTime,
    required this.type,
    required this.category,
    required this.description,
    required this.amount,
    this.paymentMethod = 'Cash',
    this.merchant = '',
    this.notes = '',
    required this.source,
    this.isSynced = 0,
  });

  TransactionModel copyWith({
    int? id,
    String? chatId,
    String? transactionDate,
    String? transactionTime,
    String? type,
    String? category,
    String? description,
    double? amount,
    String? paymentMethod,
    String? merchant,
    String? notes,
    String? source,
    int? isSynced,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      transactionDate: transactionDate ?? this.transactionDate,
      transactionTime: transactionTime ?? this.transactionTime,
      type: type ?? this.type,
      category: category ?? this.category,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      merchant: merchant ?? this.merchant,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'transaction_date': transactionDate,
      'transaction_time': transactionTime,
      'type': type,
      'category': category,
      'description': description,
      'amount': amount,
      'payment_method': paymentMethod,
      'merchant': merchant,
      'notes': notes,
      'source': source,
      'is_synced': isSynced,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      chatId: map['chat_id'] ?? 'local_user',
      transactionDate: map['transaction_date'],
      transactionTime: map['transaction_time'],
      type: map['type'],
      category: map['category'],
      description: map['description'],
      amount: (map['amount'] as num).toDouble(),
      paymentMethod: map['payment_method'] ?? 'Cash',
      merchant: map['merchant'] ?? '',
      notes: map['notes'] ?? '',
      source: map['source'] ?? 'manual',
      isSynced: map['is_synced'] ?? 0,
    );
  }
}
