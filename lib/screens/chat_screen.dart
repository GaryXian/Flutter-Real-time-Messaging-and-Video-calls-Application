import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  String? _currentUserId;
  String? _otherUserId;
  String? _otherUserName;

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser?.uid;
    _otherUserId = widget.participants.firstWhere(
      (id) => id != _currentUserId,
      orElse: () => '',
    );
    _loadOtherUserInfo();
    _markMessagesAsRead();
  }

  Future<void> _loadOtherUserInfo() async {
    if (_otherUserId == null || _otherUserId!.isEmpty) return;
    
    final userDoc = await _firestore.collection('users').doc(_otherUserId).get();
    if (mounted) {
      setState(() {
        _otherUserName = userDoc['displayName'];
      });
    }
  }

  Future<void> _markMessagesAsRead() async {
    if (_currentUserId == null || widget.conversationId.isEmpty) return;

    // Mark all unread messages as read
    final unreadMessages = await _firestore
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .where('senderId', isEqualTo: _otherUserId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in unreadMessages.docs) {
      batch.update(doc.reference, {'isRead': true, 'readAt': Timestamp.now()});
    }
    await batch.commit();

    // Update conversation unread count
    await _firestore
        .collection('conversations')
        .doc(widget.conversationId)
        .update({
          'unreadCount.$_currentUserId': 0,
        });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _otherUserName != null
            ? Text(_otherUserName!)
            : const Text('Chat'),
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
              stream: _firestore
                  .collection('conversations')
                  .doc(widget.conversationId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (ctx, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Scroll to bottom when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                final messages = snapshot.data!.docs;

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
      builder: (ctx) => FutureBuilder(
        future: _firestore.collection('users').doc(_otherUserId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final user = snapshot.data!.data() ?? {};

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: user['photoURL'] != null
                      ? NetworkImage(user['photoURL'])
                      : null,
                  child: user['photoURL'] == null
                      ? const Icon(Icons.person, size: 40)
                      : null,
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

    if (confirm == true) {
      try {
        // First delete all messages
        final messages = await _firestore
            .collection('conversations')
            .doc(widget.conversationId)
            .collection('messages')
            .get();

        final batch = _firestore.batch();
        for (final doc in messages.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        // Then delete the conversation
        await _firestore
            .collection('conversations')
            .doc(widget.conversationId)
            .delete();

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
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}