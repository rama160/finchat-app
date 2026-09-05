import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_message_model.dart';
import '../models/transaction_model.dart';
import '../services/database_helper.dart';
import '../services/gemini_service.dart';
import '../services/prefs_service.dart';
import '../services/transaction_parser.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessageModel> _messages = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await DatabaseHelper.instance.getChatMessages();
    if (!mounted) return;
    setState(() {
      _messages = history;
      if (_messages.isEmpty) {
        _messages = [
          ChatMessageModel(
            role: 'assistant',
            content:
                'Halo! Saya Finchat AI. Kamu bisa mencatat beberapa transaksi sekaligus, misalnya:\n\n'
                'beli nasi 25rb, rokok 30 rb, es 10 rb\n\n'
                'Saya akan memisahkannya dan memberi kategori otomatis.',
            timestamp: DateTime.now().toIso8601String(),
          ),
        ];
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final userMsg = ChatMessageModel(
      role: 'user',
      content: text,
      timestamp: DateTime.now().toIso8601String(),
    );

    setState(() {
      _messages = [..._messages, userMsg];
      _sending = true;
      _inputController.clear();
    });
    await DatabaseHelper.instance.insertChatMessage(userMsg);
    _scrollToBottom();

    try {
      // 1. Jalur offline-first: transaksi sederhana tidak memerlukan API.
      final localTransactions = TransactionParser.parseMany(text);
      if (localTransactions.isNotEmpty) {
        final saved = await _saveTransactions(localTransactions, source: 'chat');
        final currency = NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
        final lines = saved.map((tx) =>
            '• ${tx.description} — ${tx.category} — ${currency.format(tx.amount)}');
        await _addAssistantMessage(
          '✅ ${saved.length} transaksi berhasil dicatat:\n${lines.join('\n')}',
        );
        return;
      }

      // 2. Jalur AI: pertanyaan finansial atau kalimat transaksi yang kompleks.
      final apiKey = await PrefsService.getApiKey();
      final proxyUrl = await PrefsService.getAiProxyUrl();
      if (apiKey.isEmpty && proxyUrl.trim().isEmpty) {
        await _addAssistantMessage(
          'Saya belum mengenali itu sebagai transaksi sederhana. Untuk pertanyaan AI atau kalimat yang lebih kompleks, isi API Key Gemini di Pengaturan.',
        );
        return;
      }

      final yearMonth = DateFormat('yyyy-MM').format(DateTime.now());
      final monthTx = await DatabaseHelper.instance.getTransactionsByMonth(yearMonth);
      final summary = DatabaseHelper.instance.summarize(monthTx);

      final result = await GeminiService.processChatMessage(
        apiKey: apiKey,
        userText: text,
        financeContext: summary,
        proxyUrl: proxyUrl,
      );

      var replyText = (result['reply'] ?? '').toString();
      if (result['intent'] == 'transaction' && result['transaction'] != null) {
        final map = Map<String, dynamic>.from(result['transaction']);
        final saved = await _saveTransactions([map], source: 'chat');
        if (saved.isNotEmpty) {
          final currency = NumberFormat.currency(
              locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
          final tx = saved.first;
          replyText +=
              '\n\n✅ Transaksi tersimpan: ${tx.description} (${currency.format(tx.amount)})';
        }
      }

      await _addAssistantMessage(
        replyText.isNotEmpty ? replyText : 'Baik, sudah saya proses.',
      );
    } catch (e) {
      await _addAssistantMessage('Maaf, terjadi kesalahan: ${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<List<TransactionModel>> _saveTransactions(
      List<Map<String, dynamic>> items, {required String source}) async {
    final now = DateTime.now();
    final saved = <TransactionModel>[];
    for (final map in items) {
      final amount = double.tryParse(map['amount'].toString()) ?? 0;
      if (amount <= 0) continue;

      final tx = TransactionModel(
        transactionDate: DateFormat('yyyy-MM-dd').format(now),
        transactionTime: DateFormat('HH:mm:ss').format(now),
        type: map['type'] == 'income' ? 'income' : 'expense',
        category: (map['category'] ?? 'Lainnya').toString(),
        description: (map['description'] ?? 'Transaksi').toString(),
        amount: amount,
        merchant: (map['merchant'] ?? '').toString(),
        source: source,
      );
      await DatabaseHelper.instance.insertTransaction(tx);
      saved.add(tx);
    }
    if (saved.isNotEmpty) {
      unawaited(_syncInBackground());
    }
    return saved;
  }

  Future<void> _syncInBackground() async {
    try {
      await SheetsService.syncUnsyncedTransactions();
    } catch (_) {
      // Sinkronisasi cloud tidak boleh mengganggu pencatatan offline.
    }
  }

  Future<void> _addAssistantMessage(String text) async {
    final message = ChatMessageModel(
      role: 'assistant',
      content: text,
      timestamp: DateTime.now().toIso8601String(),
    );
    if (mounted) setState(() => _messages = [..._messages, message]);
    await DatabaseHelper.instance.insertChatMessage(message);
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.contains('Failed host lookup') || message.contains('SocketException')) {
      return 'Internet/DNS tidak tersedia. Pencatatan transaksi sederhana tetap dapat dilakukan tanpa internet.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat AI Keuangan'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.teal : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg.content,
                      style: TextStyle(
                          color: isUser ? Colors.white : Colors.black87),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Contoh: nasi 25rb, rokok 30rb, es 10rb',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _sending ? null : _handleSend,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
