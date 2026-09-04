import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_message_model.dart';
import '../models/transaction_model.dart';
import '../services/database_helper.dart';
import '../services/gemini_service.dart';
import '../services/prefs_service.dart';

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

  Future<void> _loadHistory() async {
    final history = await DatabaseHelper.instance.getChatMessages();
    setState(() {
      _messages = history;
      if (_messages.isEmpty) {
        _messages = [
          ChatMessageModel(
            role: 'assistant',
            content:
                'Halo! Saya asisten keuangan Finchat AI. Ceritakan transaksi kamu '
                '(mis. "beli kopi 20000") atau tanya soal keuangan kamu, mis. '
                '"berapa pengeluaran saya bulan ini?".',
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

    final apiKey = await PrefsService.getApiKey();
    if (apiKey.isEmpty) {
      _showNeedApiKeyDialog();
      return;
    }

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
      final yearMonth = DateFormat('yyyy-MM').format(DateTime.now());
      final monthTx = await DatabaseHelper.instance.getTransactionsByMonth(yearMonth);
      final summary = DatabaseHelper.instance.summarize(monthTx);

      final result = await GeminiService.processChatMessage(
        apiKey: apiKey,
        userText: text,
        financeContext: summary,
      );

      String replyText = (result['reply'] ?? '').toString();

      if (result['intent'] == 'transaction' && result['transaction'] != null) {
        final map = Map<String, dynamic>.from(result['transaction']);
        final now = DateTime.now();
        final newTx = TransactionModel(
          transactionDate: (map['transaction_date'] as String?)?.isNotEmpty == true
              ? map['transaction_date']
              : DateFormat('yyyy-MM-dd').format(now),
          transactionTime: DateFormat('HH:mm:ss').format(now),
          type: (map['type'] == 'income') ? 'income' : 'expense',
          category: (map['category'] ?? 'Lainnya').toString(),
          description: (map['description'] ?? text).toString(),
          amount: double.tryParse(map['amount'].toString()) ?? 0.0,
          merchant: (map['merchant'] ?? '').toString(),
          source: 'chat',
        );
        await DatabaseHelper.instance.insertTransaction(newTx);

        final currency = NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
        replyText +=
            '\n\n✅ Transaksi tersimpan: ${newTx.description} (${currency.format(newTx.amount)})';
      }

      final assistantMsg = ChatMessageModel(
        role: 'assistant',
        content: replyText.isNotEmpty
            ? replyText
            : 'Baik, sudah saya catat.',
        timestamp: DateTime.now().toIso8601String(),
      );

      setState(() {
        _messages = [..._messages, assistantMsg];
      });
      await DatabaseHelper.instance.insertChatMessage(assistantMsg);
    } catch (e) {
      final errorMsg = ChatMessageModel(
        role: 'assistant',
        content: 'Maaf, terjadi kesalahan: $e',
        timestamp: DateTime.now().toIso8601String(),
      );
      setState(() {
        _messages = [..._messages, errorMsg];
      });
    } finally {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _showNeedApiKeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API Key Diperlukan'),
        content: const Text(
            'Atur API Key Gemini kamu terlebih dahulu di halaman Pengaturan agar Chat AI bisa digunakan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Oke'),
          ),
        ],
      ),
    );
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
                      decoration: const InputDecoration(
                        hintText: 'Tulis transaksi atau tanya sesuatu...',
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
