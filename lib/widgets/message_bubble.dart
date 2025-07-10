import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import 'message_input.dart';

class MessageBubble extends StatefulWidget {
  final String messageId;
  final String senderId;
  final String content;
  final String messageType;
  final String? fileUrl;
  final String? fileType;
  final Timestamp timestamp;
  final bool isMe;
  final String conversationId;
  final bool isTyping;
  final bool isDeleted; // New field to track deleted status
  final Map<String, String>? reaction; // New field for reactions

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
    this.isDeleted = false,
    this.reaction,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final ValueNotifier<MessageBubble?> replyNotifier = ValueNotifier(null);

  Timer? _typingTimer;

  bool _isTyping = false;

  final _messageController = TextEditingController();

  final _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  final _conversationId = 'your_conversation_id'; 
  Future<void> _deleteMessage(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Message?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        final messageRef = FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId)
            .collection('messages')
            .doc(widget.messageId);

        // Get the message before deleting it
        final messageSnapshot = await messageRef.get();

        await messageRef.delete();

        // Update conversation lastMessage if needed
        final conversation =
            await FirebaseFirestore.instance
                .collection('conversations')
                .doc(widget.conversationId)
                .get();

        if (conversation.exists &&
            conversation.data()?['lastMessageId'] == widget.messageId) {
          await _updateLastMessageAfterDeletion(widget.conversationId);
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

  Future<void> _downloadFile(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch $url');
    }
  }

  Future<void> _downloadImage(BuildContext context, String imageUrl) async {
    try {
      // Request permission (needed for Android)
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Storage permission denied')));
          return;
        }
      }

      final tempDir = await getTemporaryDirectory();
      final filename = Uri.parse(imageUrl).pathSegments.last;
      final savePath = '${tempDir.path}/$filename';

      final dio = Dio();

      // Show download start
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Downloading $filename...')));

      await dio.download(
        imageUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            debugPrint(
              'Download: ${(received / total * 100).toStringAsFixed(0)}%',
            );
          }
        },
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Downloaded to $savePath')));

      // Optionally: open the file or share it
    } catch (e) {
      debugPrint('Download error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed')));
    }
  }

  Widget _buildMessageContent(BuildContext context) {
    // If the message is deleted, show deleted message indicator
    if (widget.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.not_interested, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            'Message deleted',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: widget.isMe ? Colors.white70 : Colors.grey[600],
            ),
          ),
        ],
      );
    }

    // Original content display logic
    switch (widget.messageType) {
      case 'image':
        return widget.fileUrl != null
            ? GestureDetector(
              onTap: () => _showFullScreenImage(context, widget.fileUrl!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  widget.fileUrl!,
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
        return GestureDetector(
          onTap: () {
            if (widget.fileUrl != null) {
              _downloadFile(widget.fileUrl!);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.insert_drive_file, size: 40),
              const SizedBox(height: 8),
              Text(
                widget.content.isNotEmpty ? widget.content : 'Sent a file',
                style: TextStyle(
                  fontSize: 16,
                  color: widget.isMe ? Colors.white : Colors.black87,
                ),
              ),
              if (widget.fileUrl != null)
                Text(
                  'Tap to download',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isMe ? Colors.white70 : Colors.black54,
                  ),
                ),
            ],
          ),
        );

      default:
        return Text(
          widget.content,
          style: TextStyle(
            fontSize: 16,
            color: widget.isMe ? Colors.white : Colors.black87,
          ),
        );
    }
  }

  void _replyMessage(BuildContext context) {
    final replyData = ReplyData(
      messageId: widget.messageId,
      content: widget.content,
      senderId: widget.senderId,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Functionality to reply to message is not implemented yet.',
        ),
      ),
    );
  }

  void _editMessage(BuildContext context) async {
    // Prevent editing deleted messages
    if (widget.isDeleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This message has been deleted.')),
      );
      return;
    }

    final controller = TextEditingController(text: widget.content);
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
        newContent != widget.content) {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages')
          .doc(widget.messageId)
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
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(_conversationId)
          .update({'typingUsers.$_currentUserId': true});
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(_conversationId)
          .update({'typingUsers.$_currentUserId': false});
    });
    TextField(
      controller: _messageController,
      onChanged: _handleTyping,
      decoration: InputDecoration(hintText: 'Type a message...'),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: InteractiveViewer(child: Image.network(imageUrl)),
            ),
          ),
    );
  }

  void _copyMessage(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied to clipboard')),
    );
  }

  Color _getBubbleColor() {
    if (widget.isDeleted) {
      return widget.isMe ? Colors.blueGrey.withOpacity(0.5) : Colors.grey[200]!;
    }

    if (widget.messageType == 'image' || widget.messageType == 'video' && widget.isMe) {
      return Colors.transparent; // No background for user's image
    }

    if (widget.isMe) {
      return Colors.blueAccent;
    } else {
      return widget.messageType == 'text' ? Colors.grey[300]! : Colors.grey[200]!;
    }
  }

void _showOverlayWithMenus(BuildContext context, bool canDelete) {
  final RenderBox renderBox = context.findRenderObject() as RenderBox;
  final messagePosition = renderBox.localToGlobal(Offset.zero);
  final messageSize = renderBox.size;
  final screenSize = MediaQuery.of(context).size;

  final overlay = Overlay.of(context);
  late OverlayEntry overlayEntry;

  // Calculate safe menu position (bottom right by default)
  const double menuWidth = 120;
  const double menuHeightEstimate = 200; // approximate menu height
  double dx = messagePosition.dx + messageSize.width - menuWidth;
  double dy = messagePosition.dy + messageSize.height;

  // Clamp to screen bounds
  dx = dx.clamp(8.0, screenSize.width - menuWidth - 8.0);
  dy = dy.clamp(8.0, screenSize.height - menuHeightEstimate - 8.0);

  overlayEntry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        // Dismiss on tap outside
        Positioned.fill(
          child: GestureDetector(
            onTap: () => overlayEntry.remove(),
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),

        // Options menu
        Positioned(
          left: dx,
          top: dy,
          child: _buildOptionsMenu(
            context,
            Offset(dx, dy),
            _buildMenuItems(context, canDelete, overlayEntry),
          ),
        ),
      ],
    ),
  );

  overlay.insert(overlayEntry);
}

List<Widget> _buildMenuItems(
  BuildContext context,
  bool canDelete,
  OverlayEntry overlayEntry,
) {
  final List<Widget> items = [];

  if (widget.messageType == 'text') {
    items.add(_buildOptionItem(
      'Copy',
      Icons.copy,
      () {
        overlayEntry.remove();
        Clipboard.setData(ClipboardData(text: widget.content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message copied')),
        );
      },
    ));
    items.add(const Divider(height: 1));
  }
/*
  items.add(_buildOptionItem(
    'Reply',
    Icons.reply,
    () {
      overlayEntry.remove();
      _replyMessage(context);
    },
  ));
*/
  if (canDelete) {
    items.add(const Divider(height: 1));
    items.add(_buildOptionItem(
      'Edit',
      Icons.edit_outlined,
      () {
        overlayEntry.remove();
        _editMessage(context);
      },
    ));
    items.add(const Divider(height: 1));
    items.add(_buildOptionItem(
      'Delete',
      Icons.delete_outline,
      () {
        overlayEntry.remove();
        _deleteMessage(context);
      },
      textColor: Colors.red,
      iconColor: Colors.red,
    ));
  }

  return items;
}

Widget _buildEmojiBar(BuildContext context, Offset position, OverlayEntry overlayEntry) {
  return Positioned(
    left: position.dx,
    top: position.dy,
    child: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildEmojiButton('❤️', overlayEntry),
            _buildEmojiButton('👍', overlayEntry),
            _buildEmojiButton('😂', overlayEntry),
            _buildEmojiButton('😮', overlayEntry),
            _buildEmojiButton('😢', overlayEntry),
            _buildEmojiButton('🙏', overlayEntry),
          ],
        ),
      ),
    ),
  );
}

Widget _buildOptionsMenu(BuildContext context, Offset position, List<Widget> items) {
  return Positioned(
    left: position.dx,
    top: position.dy,
    child: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items,
        ),
      ),
    ),
  );
}

  Widget _buildOptionItem(
    String label,
    IconData icon,
    VoidCallback onTap, {
    Color iconColor = Colors.black87,
    Color textColor = Colors.black87,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiButton(String emoji, OverlayEntry overlayEntry) {
    return InkWell(
      onTap: () {
        // Add reaction
        _addReaction(emoji);
        overlayEntry.remove();
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }

  void _addReaction(String emoji) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    // Create a new map if reactions are null
    final updatedReactions = widget.reaction ?? {};
    updatedReactions[currentUserId] = emoji;

    // Update the message in Firestore
    FirebaseFirestore.instance.collection('messages').doc(widget.messageId).update({
      'reaction': updatedReactions,
    });
  }

@override
Widget build(BuildContext context) {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final canDelete = widget.senderId == currentUserId && !widget.isDeleted;
  final timeString = DateFormat('h:mm a').format(widget.timestamp.toDate());

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!widget.isMe) // Show profile picture for received messages
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildUserAvatar(widget.senderId),
          ),
        Flexible(
          child: Align(
            alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              child: GestureDetector(
                onLongPress: () {
                  if (widget.isDeleted) return;
                  _showOverlayWithMenus(context, canDelete);
                },
                child: AbsorbPointer(
                  absorbing: widget.isDeleted,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getBubbleColor(),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(widget.isMe ? 16 : 0),
                        bottomRight: Radius.circular(widget.isMe ? 0 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (!widget.isMe && !widget.isDeleted)
                          FutureBuilder(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .doc(widget.senderId)
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
                        _buildMessageContent(context),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeString,
                              style: TextStyle(
                                fontSize: 10,
                                color: widget.isMe ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            if (widget.isMe && !widget.isDeleted)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.done_all,
                                  size: 12,
                                  color: widget.isMe ? Colors.white70 : Colors.black54,
                                ),
                              ),
                          ],
                        ),
                        if (widget.reaction != null && widget.reaction!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ...widget.reaction!.values.toSet().map((emoji) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  );
                                }).toList(),
                                if (widget.reaction!.length > 1)
                                  Text(
                                    widget.reaction!.length.toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.isMe) // Show profile picture for sent messages (smaller)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _buildUserAvatar(currentUserId, small: true),
          ),
      ],
    ),
  );
}

Widget _buildUserAvatar(String? userId, {bool small = false}) {
  if (userId == null) return const SizedBox();

  return StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots(),
    builder: (context, snapshot) {
      final photoUrl = snapshot.data?.get('photoURL');
      final displayName = snapshot.data?.get('displayName') ?? '?';
      
      return CircleAvatar(
        radius: small ? 14 : 18,
        backgroundColor: Colors.grey[300],
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
        child: photoUrl == null
            ? Text(
                displayName.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: small ? 12 : 14,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      );
    },
  );
}
}

