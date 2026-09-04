class ChatMessageModel {
  final int? id;
  final String role; // 'user' atau 'assistant'
  final String content;
  final String timestamp;
  final int? relatedTransactionId;

  ChatMessageModel({
    this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.relatedTransactionId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'timestamp': timestamp,
      'related_transaction_id': relatedTransactionId,
    };
  }

  factory ChatMessageModel.fromMap(Map<String, dynamic> map) {
    return ChatMessageModel(
      id: map['id'],
      role: map['role'],
      content: map['content'],
      timestamp: map['timestamp'],
      relatedTransactionId: map['related_transaction_id'],
    );
  }
}
