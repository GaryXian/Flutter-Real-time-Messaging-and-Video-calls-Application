import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:realtime_message_calling/main_screens/messages_screen.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import 'call_screen.dart';

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
  final ValueNotifier<ReplyData?> replyNotifier = ValueNotifier(null);
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
    _otherUserId = widget.participants.firstWhere(
      (id) => id != _currentUserId,
      orElse: () => '',
    );

    _loadOtherUserInfo();
  }

  Future<void> _loadOtherUserInfo() async {
    if (_otherUserId.isEmpty) return;
    final userDoc =
        await _firestore.collection('users').doc(_otherUserId).get();
    if (userDoc.exists && mounted) {
      setState(() {
        _otherUserName = userDoc['displayName'];
      });
    }
  }

  bool _isLoadingMore = false;
  DocumentSnapshot? _lastDocument;

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final query = _firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(20); // Adjust limit as needed

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        // You'll need to merge these new messages with your existing ones
        // This depends on how you're managing your message stream
      }
    } catch (e) {
      debugPrint('Error loading more messages: $e');
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _markMessagesAsReadOnce() async {
    if (_messagesMarkedAsRead) return;
    _messagesMarkedAsRead = true;

    final unreadMessages =
        await _firestore
            .collection('conversations')
            .doc(widget.conversationId)
            .collection('messages')
            .where('senderId', isEqualTo: _otherUserId)
            .where('isRead', isEqualTo: false)
            .get();

    if (unreadMessages.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unreadMessages.docs) {
      batch.update(doc.reference, {'isRead': true, 'readAt': Timestamp.now()});
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

  void _startVideoCall(bool isVideoCall) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (ctx) => CallScreen(
              conversationId: widget.conversationId,
              callerId: _currentUserId,
              receiverId: _otherUserId,
              isVideoCall: true,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messageStream =
        _firestore
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
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _startVideoCall(true),
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
                final messages =
                    snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final hiddenFor = data['hiddenFor'] as List<dynamic>?;
                      return hiddenFor == null ||
                          !hiddenFor.contains(_currentUserId);
                    }).toList();

                // Mark as read only on first load with data
                _markMessagesAsReadOnce();

                // Scroll to bottom only when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (messages.isNotEmpty) {
                    _scrollToBottom();
                  }
                });

                return NotificationListener<ScrollNotification>(
                  onNotification: (scrollNotification) {
                    if (scrollNotification is ScrollEndNotification &&
                        _scrollController.position.extentBefore == 0 &&
                        !_isLoadingMore) {
                      _loadMoreMessages();
                      return true;
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: messages.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (ctx, index) {
                      // Show loading indicator at the top when loading more messages
                      if (_isLoadingMore && index == messages.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      // Adjust index if we're loading more
                      final messageIndex = _isLoadingMore ? index : index;
                      if (messageIndex >= messages.length) return Container();

                      final message = messages[messageIndex];
                      final data = message.data() as Map<String, dynamic>;
                      final messageType = data['messageType'] ?? 'text';

                      if (messageType == 'call') {
                        final isMe = data['senderId'] == _currentUserId;
                        final callType = data['callType'] ?? 'voice';
                        final status = data['status'] ?? 'missed';
                        final timestamp = data['timestamp'];
                        final time =
                            (timestamp is Timestamp)
                                ? timestamp.toDate()
                                : DateTime.now();

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: Card(
                              color:
                                  status == 'accepted'
                                      ? Colors.green[100]
                                      : Colors.red[100],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 12,
                                ),
                                child: Text(
                                  '${isMe ? "You" : _otherUserName} '
                                  '${status == "accepted" ? "answered" : status} '
                                  'a $callType call\n${DateFormat('MMM d, h:mm a').format(time)}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        status == 'accepted'
                                            ? Colors.green[800]
                                            : Colors.red[800],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      } else {
                        // Handle text, image, or file messages
                        final content =
                            data.containsKey('content') ? data['content'] : '';
                        final senderId = data['senderId'] ?? '';
                        final timestamp = data['timestamp'] ?? Timestamp.now();
                        final fileUrl =
                            data.containsKey('fileUrl')
                                ? data['fileUrl']
                                : null;
                        final fileType =
                            data.containsKey('fileType')
                                ? data['fileType']
                                : null;

                        return MessageBubble(
                          key: ValueKey(message.id),
                          messageId: message.id,
                          senderId: senderId,
                          content: content,
                          messageType: messageType,
                          timestamp: timestamp as Timestamp,
                          isMe: senderId == _currentUserId,
                          conversationId: widget.conversationId,
                          fileUrl: fileUrl,
                          fileType: fileType,
                        );
                      }
                    },
                  ),
                );
              },
            ),
          ),
          // Your message input widget here
          MessageInput(
            conversationId: widget.conversationId,
            participants: widget.participants,
            onSend: () {
              _scrollToBottom();
            },
          ),
        ],
      ),
    );
  }

  void _showChatInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => FutureBuilder<DocumentSnapshot>(
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
                      backgroundImage:
                          user['photoURL'] != null
                              ? NetworkImage(user['photoURL'])
                              : null,
                      child:
                          user['photoURL'] == null
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
                    /*
                    ListTile(
                      
                      leading: const Icon(Icons.delete),
                      title: const Text('Delete conversation'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _confirmDeleteConversation(context);
                      },
                      
                    ),
                    */
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
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Conversation?'),
            content: const Text(
              'All messages and calls will be permanently deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      final batch = _firestore.batch();

      // Delete messages
      final messagesRef = _firestore
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages');
      final messages = await messagesRef.get();
      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }

      // Delete call data (calls + iceCandidates)
      final callDocRef = _firestore
          .collection('calls')
          .doc(widget.conversationId);
      final callDoc = await callDocRef.get();
      if (callDoc.exists) {
        final candidatesRef = callDocRef.collection('iceCandidates');
        final candidates = await candidatesRef.get();
        for (final doc in candidates.docs) {
          batch.delete(doc.reference);
        }
        batch.delete(callDocRef);
      }

      // Delete conversation document
      final conversationRef = _firestore
          .collection('conversations')
          .doc(widget.conversationId);
      batch.delete(conversationRef);

      await batch.commit();

      if (!context.mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MessagesScreen()),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
