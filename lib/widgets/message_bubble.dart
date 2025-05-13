import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MessageBubble extends StatelessWidget {
  final String messageId;
  final String senderId;
  final String content;
  final String messageType;
  final String? fileUrl;
  final String? fileType;
  final Timestamp timestamp;
  final bool isMe;
  final String conversationId;
  Timer? _typingTimer;
  bool _isTyping = false;
  final _messageController = TextEditingController();
  final _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final _conversationId = 'your_conversation_id'; // dynamically assigned
  final bool isTyping;
  final bool isDeleted; // New field to track deleted status

  MessageBubble({
    super.key,
    required this.messageId,
    required this.senderId,
    required this.content,
    required this.messageType,
    required this.timestamp,
    required this.isMe,
    required this.conversationId,
    this.fileUrl,
    this.fileType,
    this.isTyping = false,
    this.isDeleted = false, // Default to not deleted
  });

Future<void> _deleteMessage(BuildContext context) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Message?'),
      content: const Text('This action cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirm == true) {
    try {
      final messageRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId);

      // Get the message before deleting it
      final messageSnapshot = await messageRef.get();

      await messageRef.delete(); // 🔥 Delete the message document

      // Update conversation lastMessage if needed
      final conversation = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (conversation.exists &&
          conversation.data()?['lastMessageId'] == messageId) {
        await _updateLastMessageAfterDeletion(conversationId);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${e.toString()}')),
        );
      }
    }
  }
}


  Future<void> _updateLastMessageAfterDeletion(String conversationId) async {
    final messages =
        await FirebaseFirestore.instance
            .collection('conversations')
            .doc(conversationId)
            .collection('messages')
            .where(
              'isDeleted',
              isEqualTo: false,
            ) // Only consider non-deleted messages
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

    if (messages.docs.isNotEmpty) {
      final lastMessage = messages.docs.first;
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .update({
            'lastMessage': lastMessage['content'],
            'lastMessageId': lastMessage.id,
            'lastMessageTime': lastMessage['timestamp'],
            'lastMessageType': lastMessage['messageType'],
          });
    } else {
      // No messages left in conversation
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .update({
            'lastMessage': null,
            'lastMessageId': null,
            'lastMessageTime': null,
            'lastMessageType': null,
          });
    }
  }

  Widget _buildMessageContent() {
    // If the message is deleted, show deleted message indicator
    if (isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.not_interested, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            'This message was deleted',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: isMe ? Colors.white70 : Colors.grey[600],
            ),
          ),
        ],
      );
    }

    // Original content display logic
    switch (messageType) {
      case 'image':
        return fileUrl != null
            ? GestureDetector(
              onTap: () => _showFullScreenImage(fileUrl!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  fileUrl!,
                  width: 250,
                  height: 250,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: 250,
                      height: 250,
                      color: Colors.grey[200],
                      child: Center(
                        child: CircularProgressIndicator(
                          value:
                              loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder:
                      (context, error, stackTrace) => Container(
                        width: 250,
                        height: 250,
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.broken_image)),
                      ),
                ),
              ),
            )
            : const Text('[Image not available]');
      case 'file':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.insert_drive_file, size: 40),
            const SizedBox(height: 8),
            Text(
              content.isNotEmpty ? content : 'Sent a file',
              style: TextStyle(
                fontSize: 16,
                color: isMe ? Colors.white : Colors.black87,
              ),
            ),
            if (fileUrl != null)
              Text(
                'Tap to download',
                style: TextStyle(
                  fontSize: 12,
                  color: isMe ? Colors.white70 : Colors.black54,
                ),
              ),
          ],
        );
      default:
        return Text(
          content,
          style: TextStyle(
            fontSize: 16,
            color: isMe ? Colors.white : Colors.black87,
          ),
        );
    }
  }

  void _showEmojiReactionMenu(BuildContext context) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => Wrap(
            children:
                emojis.map((emoji) {
                  return ListTile(
                    title: Text(emoji, style: TextStyle(fontSize: 24)),
                    onTap: () async {
                      final uid = FirebaseAuth.instance.currentUser!.uid;
                      final msgRef = FirebaseFirestore.instance
                          .collection('conversations')
                          .doc(conversationId)
                          .collection('messages')
                          .doc(messageId);
                      await msgRef.set({
                        'reactions.$uid': emoji,
                      }, SetOptions(merge: true));
                      Navigator.of(ctx).pop();
                    },
                  );
                }).toList(),
          ),
    );
  }

  void _editMessage(BuildContext context) async {
    final controller = TextEditingController(text: content);
    final newContent = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Edit Message'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Edit your message'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (newContent != null &&
        newContent.trim().isNotEmpty &&
        newContent != content) {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .update({
            'content': newContent.trim(),
            'edited': true,
            'editedAt': FieldValue.serverTimestamp(),
          });
    }
  }
  void _handleTyping(String text) {
  if (!_isTyping) {
    _isTyping = true;
    FirebaseFirestore.instance.collection('conversations').doc(_conversationId).update({
      'typingUsers.$_currentUserId': true,
    });
  }

  _typingTimer?.cancel();
  _typingTimer = Timer(const Duration(seconds: 2), () {
    _isTyping = false;
    FirebaseFirestore.instance.collection('conversations').doc(_conversationId).update({
      'typingUsers.$_currentUserId': false,
    });
  });
  TextField(
  controller: _messageController,
  onChanged: _handleTyping,
  decoration: InputDecoration(hintText: 'Type a message...'),
);

}


  void _showFullScreenImage(String imageUrl) {
    // Implement full screen image viewer
    // Could use a package like photo_view
  }

  Color _getBubbleColor() {
    if (isDeleted) {
      // Use subdued colors for deleted messages
      return isMe ? Colors.blueGrey.withOpacity(0.5) : Colors.grey[200]!;
    }

    if (isMe) {
      return messageType == 'text'
          ? Colors.blueAccent
          : Colors.blueAccent.withOpacity(0.9);
    } else {
      return messageType == 'text' ? Colors.grey[300]! : Colors.grey[200]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final canDelete =
        senderId == currentUserId &&
        !isDeleted; // Can't delete already deleted messages
    final timeString = DateFormat('h:mm a').format(timestamp.toDate());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: GestureDetector(
            onLongPress: () {
              if (canDelete) {
                showModalBottomSheet(
                  context: context,
                  builder:
                      (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.edit),
                              title: const Text('Edit'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _editMessage(context);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete),
                              title: const Text('Delete'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _deleteMessage(context);
                              },
                            ),
                          ],
                        ),
                      ),
                );
              }
            },

            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getBubbleColor(),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 0),
                  bottomRight: Radius.circular(isMe ? 0 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe &&
                      !isDeleted) // Don't show username for deleted messages
                    FutureBuilder(
                      future:
                          FirebaseFirestore.instance
                              .collection('users')
                              .doc(senderId)
                              .get(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final user = snapshot.data!.data();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              user?['displayName'] ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  _buildMessageContent(),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeString,
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      if (isMe &&
                          !isDeleted) // Don't show read indicators for deleted messages
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.done_all,
                            size: 12,
                            color: isMe ? Colors.white70 : Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
