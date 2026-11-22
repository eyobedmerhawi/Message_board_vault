import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/board_service.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final BoardService _boardService = BoardService();
  final AuthService _authService = AuthService();
  final TextEditingController _messageController = TextEditingController();

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messageStream;

  bool _isPosting = false;
  bool _isLoggingOut = false;
  final Set<String> _busyMessages = {};

  @override
  void initState() {
    super.initState();
    _messageStream = _boardService.getMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Error: $error')));
  }

  Future<void> _postMessage() async {
    if (_isPosting) return;

    final text = _messageController.text.trim();
    if (text.isEmpty) {
      _showError('Please enter a message.');
      return;
    }

    setState(() => _isPosting = true);

    try {
      await _boardService.createMessage(text);
      if (!mounted) return;

      if (_messageController.text.trim() == text) {
        _messageController.clear();
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Message posted!')));
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _editMessage(String id, String currentText) async {
    final controller = TextEditingController(text: currentText);

    final updatedText = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Message',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(dialogContext, text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (!mounted || updatedText == null || updatedText == currentText) {
      return;
    }

    setState(() => _busyMessages.add(id));

    try {
      await _boardService.updateMessage(id, updatedText);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busyMessages.remove(id));
    }
  }

  Future<void> _deleteMessage(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => _busyMessages.add(id));

    try {
      await _boardService.deleteMessage(id);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busyMessages.remove(id));
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    setState(() => _isLoggingOut = true);

    try {
      await _authService.logout();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  Widget _buildMessage(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    final id = document.id;
    final text = data['text'] as String? ?? '';
    final authorName = data['authorName'] as String? ?? 'Unknown';
    final authorUid = data['authorUid'] as String? ?? '';
    final isOwner = FirebaseAuth.instance.currentUser?.uid == authorUid;
    final isBusy = _busyMessages.contains(id);
    final isEdited = data['editedAt'] != null;

    final createdAt = data['createdAt'];
    final dateText = createdAt is Timestamp
        ? createdAt.toDate().toLocal().toString().substring(0, 16)
        : 'Just now';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE98B39),
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authorName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$dateText${isEdited ? ' • Edited' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isOwner)
                  PopupMenuButton<String>(
                    enabled: !isBusy,
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editMessage(id, text);
                      } else if (value == 'delete') {
                        _deleteMessage(id);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(fontSize: 16)),
            if (isBusy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Message Board Vault'),
        backgroundColor: const Color(0xFFE98B39),
        actions: [
          IconButton(
            tooltip: 'Log Out',
            onPressed: _isLoggingOut ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messageStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Unable to load messages. Please try again.'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Be the first to post!',
                      style: TextStyle(fontSize: 16),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _buildMessage(messages[index]);
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: !_isPosting,
                      maxLines: 3,
                      minLines: 1,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText: 'Write a message...',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Post Message',
                    onPressed: _isPosting ? null : _postMessage,
                    icon: _isPosting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
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
