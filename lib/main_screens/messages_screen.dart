import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../screens/chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Map<String, dynamic>> _userCache = {};
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoadingUsers = false;

  String _generateConversationId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }

  Future<void> _startNewConversation(
    String contactId,
    String contactName,
  ) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    final conversationId = _generateConversationId(currentUserId, contactId);

    try {
      // Check if conversation exists
      final conversationDoc =
          await _firestore
              .collection('conversations')
              .doc(conversationId)
              .get();

      if (!conversationDoc.exists) {
        await _firestore.collection('conversations').doc(conversationId).set({
          'conversationId': conversationId,
          'participants': [currentUserId, contactId],
          'participantNames': {
            currentUserId: _auth.currentUser?.displayName ?? 'You',
            contactId: contactName,
          },
          'lastMessage': 'Conversation started',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'unreadCount': {
            currentUserId: 0,
            contactId: 1, // Mark as unread for the recipient
          },
        });
      } else {
        // Update unread count if conversation already exists
        await _firestore.collection('conversations').doc(conversationId).update({
          'lastMessage': 'Conversation resumed',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCount.$currentUserId': FieldValue.increment(1),
          //'unreadCount.$contactId': FieldValue.increment(1),
        });
      }

      if (!mounted) return;
      _openChatRoom(context, contactId, contactName, conversationId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start conversation: ${e.toString()}'),
        ),
      );
    }
  }

  void _openChatRoom(
    BuildContext context,
    String contactId,
    String contactName,
    String conversationId,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (ctx) => ChatScreen(
              conversationId: conversationId,
              participants: [_auth.currentUser!.uid, contactId],
            ),
      ),
    );
  }

  Future<Map<String, dynamic>> _getUserInfo(String userId) async {
    if (_userCache.containsKey(userId)) {
      return _userCache[userId]!;
    }

    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data() ?? {};
    _userCache[userId] = data;
    return data;
  }

  Future<void> _loadFriends() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    setState(() => _isLoadingUsers = true);
    try {
      // Get friend list from subcollection users/{uid}/friends
      final friendsSnapshot =
          await _firestore
              .collection('users')
              .doc(currentUserId)
              .collection('friends')
              .get();

      final friendIds = friendsSnapshot.docs.map((doc) => doc.id).toSet();

      // Get users info of friends
      final friendsData = await Future.wait(
        friendIds.map((id) => _firestore.collection('users').doc(id).get()),
      );

      // Get existing conversations
      final conversationsSnapshot =
          await _firestore
              .collection('conversations')
              .where('participants', arrayContains: currentUserId)
              .get();

      final existingContacts =
          conversationsSnapshot.docs
              .expand(
                (doc) => (doc.data()['participants'] as List).cast<String>(),
              )
              .where((id) => id != currentUserId)
              .toSet();

      setState(() {
        _availableUsers =
            friendsData.where((doc) => doc.exists).map((doc) {
              final data = doc.data()!;
              return {
                'uid': doc.id,
                'displayName': data['displayName'] ?? 'Unknown',
                'email': data['email'] ?? '',
                'photoURL': data['photoURL'] ?? '',
                'hasConversation': existingContacts.contains(doc.id),
              };
            }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load friends: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoadingUsers = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('Please sign in')));
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('Messages'),
        actions: [
          IconButton(
            onPressed: () => _showNewChatDialog(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            _firestore
                .collection('conversations')
                .where('participants', arrayContains: currentUserId)
                .orderBy('lastMessageTime', descending: true)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No conversations yet'),
                  TextButton(
                    onPressed: () => _showNewChatDialog(context),
                    child: const Text('Start a new conversation'),
                  ),
                ],
              ),
            );
          }

          final conversations =
              snapshot.data!.docs
                  .map(
                    (doc) => {
                      'id': doc.id,
                      ...doc.data() as Map<String, dynamic>,
                    },
                  )
                  .toList();
          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (ctx, index) {
              final convo = conversations[index];
              final participants = List<String>.from(convo['participants']);
              final otherUserId = participants.firstWhere(
                (id) => id != currentUserId,
                orElse: () => '',
              );

              return FutureBuilder<Map<String, dynamic>>(
                future: _getUserInfo(otherUserId),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                    );
                  }

                  final userData = userSnapshot.data!;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          userData['photoURL'] != null
                              ? NetworkImage(userData['photoURL'])
                              : null,
                      child:
                          userData['photoURL'] == null
                              ? const Icon(Icons.person)
                              : null,
                    ),
                    title: Text(userData['displayName'] ?? 'Unknown'),
                    subtitle: Text(
                      convo['lastMessage'] ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatTimestamp(
                            convo['lastMessageTime'] as Timestamp?,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (convo['unreadCount']?[currentUserId] != null &&
                            convo['unreadCount'][currentUserId] > 0)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              convo['unreadCount'][currentUserId].toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onTap:
                        () => _openChatRoom(
                          context,
                          otherUserId,
                          userData['displayName'] ?? 'Unknown',
                          convo['id'],
                        ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }


  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    }
    return DateFormat('MMM d').format(date);
  }

  Future<void> _showNewChatDialog(BuildContext context) async {
    await _loadFriends();

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('New Conversation'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isLoadingUsers
                      ? const Center(child: CircularProgressIndicator())
                      : _availableUsers.isEmpty
                      ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No friends available'),
                      )
                      : Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _availableUsers.length,
                          itemBuilder: (ctx, index) {
                            final user = _availableUsers[index];
                            final alreadyChatted =
                                user['hasConversation'] == true;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage:
                                    user['photoURL'] != null
                                        ? NetworkImage(user['photoURL'])
                                        : null,
                                child:
                                    user['photoURL'] == null
                                        ? const Icon(Icons.person)
                                        : null,
                              ),
                              title: Text(user['displayName'] ?? 'Unknown'),
                              subtitle: Text(user['email'] ?? ''),
                              trailing:
                                  alreadyChatted
                                      ? const Text(
                                        'Already chatted',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      )
                                      : null,
                              enabled: !alreadyChatted,
                              onTap:
                                  alreadyChatted
                                      ? null
                                      : () {
                                        Navigator.pop(ctx);
                                        _startNewConversation(
                                          user['uid'],
                                          user['displayName'] ?? 'Unknown',
                                        );
                                      },
                            );
                          },
                        ),
                      ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
