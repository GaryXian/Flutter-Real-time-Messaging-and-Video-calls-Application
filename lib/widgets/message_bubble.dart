import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


class MessageBubble extends StatelessWidget {
  final String messageId;
  final String senderId;
  final String message;
  final String messageType;
  final String? fileUrl;
  final Timestamp timestamp;
  final bool isMe;
  final String conversationId;

  const MessageBubble({
    super.key,
    required this.messageId,
    required this.senderId,
    required this.message,
    required this.messageType,
    required this.timestamp,
    required this.isMe,
    required this.conversationId,
    this.fileUrl, required fileType,
  });

  Future<void> _deleteMessage(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text('Do you really want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .delete();
    }
  }

  Widget _buildMessageContent() {
    switch (messageType) {
      case 'image':
        return fileUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(fileUrl!, width: 200, fit: BoxFit.cover),
              )
            : const Text('[Image not available]');
      case 'file':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.insert_drive_file, size: 30),
            const SizedBox(height: 4),
            Text(
              fileUrl ?? '[File not found]',
              style: const TextStyle(fontSize: 14, color: Colors.blue),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      default:
        return Text(
          message,
          style: const TextStyle(fontSize: 16),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final canDelete = senderId == currentUserId;

    return GestureDetector(
      onLongPress: canDelete ? () => _deleteMessage(context) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[100] : Colors.grey[300],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            _buildMessageContent(),
            const SizedBox(height: 4),
            Text(
              '${timestamp.toDate().hour}:${timestamp.toDate().minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
