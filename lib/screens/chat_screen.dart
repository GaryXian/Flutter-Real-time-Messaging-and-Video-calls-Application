import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final List<String> participants;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.participants,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final String _currentUserId;
  late final String _otherUserId;

  String? _otherUserName;
  bool _messagesMarkedAsRead = false; // optimization flag

  @override
  void initState() {
    super.initState();
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('No authenticated user');
    }
    _currentUserId = userId;
    _otherUserId = widget.participants.firstWhere((id) => id != _currentUserId, orElse: () => '');

    _loadOtherUserInfo();
  }

  Future<void> _loadOtherUserInfo() async {
    if (_otherUserId.isEmpty) return;
    final userDoc = await _firestore.collection('users').doc(_otherUserId).get();
    if (userDoc.exists && mounted) {
      setState(() {
        _otherUserName = userDoc['displayName'];
      });
    }
  }

  Future<void> _markMessagesAsReadOnce() async {
    if (_messagesMarkedAsRead) return; // prevent re-trigger
    _messagesMarkedAsRead = true;

    final unreadMessages = await _firestore
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .where('senderId', isEqualTo: _otherUserId)
        .where('isRead', isEqualTo: false)
        .get();

    if (unreadMessages.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unreadMessages.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': Timestamp.now(),
      });
    }

    batch.update(
      _firestore.collection('conversations').doc(widget.conversationId),
      {'unreadCount.$_currentUserId': 0},
    );

    await batch.commit();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final messageStream = _firestore
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(_otherUserName ?? 'Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showChatInfo(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: messageStream,
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }

                final messages = snapshot.data!.docs;

                // Mark as read only on first load with data
                _markMessagesAsReadOnce();

                // Scroll to bottom only when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (messages.isNotEmpty) {
                    _scrollToBottom();
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (ctx, index) {
                    final message = messages[index];
                    return MessageBubble(
                      key: ValueKey(message.id),
                      messageId: message.id,
                      senderId: message['senderId'],
                      content: message['content'],
                      messageType: message['messageType'],
                      timestamp: message['timestamp'] as Timestamp,
                      isMe: message['senderId'] == _currentUserId,
                      conversationId: widget.conversationId,
                      fileUrl: message['fileUrl'],
                      fileType: message['fileType'],
                    );
                  },
                );
              },
            ),
          ),
          MessageInput(
            conversationId: widget.conversationId,
            participants: widget.participants,
          ),
        ],
      ),
    );
  }

  void _showChatInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('users').doc(_otherUserId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final user = snapshot.data?.data() as Map<String, dynamic>? ?? {};

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: user['photoURL'] != null ? NetworkImage(user['photoURL']) : null,
                  child: user['photoURL'] == null ? const Icon(Icons.person, size: 40) : null,
                ),
                const SizedBox(height: 16),
                Text(
                  user['displayName'] ?? 'Unknown',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  user['email'] ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete),
                  title: const Text('Delete conversation'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteConversation(context);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteConversation(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: const Text('All messages will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final messagesRef = _firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages');

      final messages = await messagesRef.get();
      final batch = _firestore.batch();

      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }

      final conversationRef = _firestore.collection('conversations').doc(widget.conversationId);
      batch.delete(conversationRef);

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
