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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, Map<String, dynamic>> _userCache = {};
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoadingUsers = false;
    bool _isLoading=false;
    bool _hasMore=true;
    int _messagesPerPage = 20;
    DocumentSnapshot? _lastDocument;
    List<QueryDocumentSnapshot> _messages = [];

  String _generateConversationId(String userId1, String userId2) {
    // Check if trying to create a self-conversation
    if (userId1 == userId2) {
      throw Exception('Cannot create a conversation with yourself');
    }

    return userId1.compareTo(userId2) < 0
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }
  

  Future<void> _startNewConversation(
    String contactId,
    String contactName,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      return;
    }

    final conversationId = _generateConversationId(currentUser.uid, contactId);

    try {
      final contactDoc =
          await _firestore.collection('users').doc(contactId).get();
      if (!contactDoc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User not found')));
        return;
      }

      final conversationDoc =
          await _firestore
              .collection('conversations')
              .doc(conversationId)
              .get();

      if (!conversationDoc.exists) {
        await _firestore.collection('conversations').doc(conversationId).set({
          'participants': [currentUser.uid, contactId],
          'participantNames': {
            currentUser.uid: currentUser.displayName ?? 'You',
            contactId: contactName,
          },
          'lastMessage': '',
          'lastMessageType': 'text',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageId': '',
          'unreadCount': {
            currentUser.uid: 0,
            contactId: 0,
          },
          'type': 'private',
          'updatedAt': FieldValue.serverTimestamp(),
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

  Future<void> _openChatRoom(
    BuildContext context,
    String contactId,
    String contactName,
    String conversationId,
  ) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final conversationDoc =
          await _firestore
              .collection('conversations')
              .doc(conversationId)
              .get();

      if (!conversationDoc.exists ||
          !(conversationDoc.data()?['participants'] as List).contains(
            currentUserId,
          )) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Conversation not found')));
        return;
      }

      // Reset unreadCount for current user
      await _firestore.collection('conversations').doc(conversationId).update({
        'unreadCount.$currentUserId': 0,
      });

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (ctx) => ChatScreen(
                conversationId: conversationId,
                participants: [currentUserId, contactId],
              ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening chat: ${e.toString()}')),
      );
    }
  }
  
Future<void> _loadMessages() async {
  // Prevent re-entrance if already loading or no more messages
  if (_isLoading || !_hasMore) return;

  setState(() => _isLoading = true);

  try {
    Query query = _firestore.collection('conversations').doc('conversationId').collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(_messagesPerPage);

    if (_lastDocument != null) {
      query = query.startAfterDocument(_lastDocument!);
    }

    final snapshot = await query.get();

    if (snapshot.docs.isNotEmpty) {
      _lastDocument = snapshot.docs.last;
      _messages.addAll(snapshot.docs);
    }

    if (snapshot.docs.length < _messagesPerPage) {
      _hasMore = false;
    }
  } catch (e) {
    debugPrint("Error loading messages: $e");
  } finally {
    setState(() => _isLoading = false);
  }
}

  

  Future<void> _loadFriends() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    setState(() => _isLoadingUsers = true);
    try {
      final friendsSnapshot =
          await _firestore
              .collection('users')
              .doc(currentUserId)
              .collection('friends')
              .get();

      final friendIds = friendsSnapshot.docs.map((doc) => doc.id).toSet();

      if (friendIds.isEmpty) {
        setState(() {
          _availableUsers = [];
        });
        return;
      }

      final usersQuery =
          await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: friendIds.toList())
              .get();

      // Preload user info into cache
      for (var doc in usersQuery.docs) {
        _userCache[doc.id] = doc.data();
      }

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
            usersQuery.docs.where((doc) => doc.exists).map((doc) {
              final data = doc.data();
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

  Map<String, dynamic> _getCachedUserInfo(String userId) {
    return _userCache[userId] ?? {'displayName': 'Unknown'};
  }

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _loadMessages();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
              _scrollController.position.minScrollExtent &&
          !_isLoading &&
          _hasMore) {
        _loadMessages();
      }
    });
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
      stream: _firestore
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

        final conversations = snapshot.data!.docs.map((doc) {
          return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
        }).toList();

        return ListView.builder(
          itemCount: conversations.length,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (ctx, index) {
            final convo = conversations[index];
            final participants = List<String>.from(convo['participants']);
            final otherUserId = participants.firstWhere(
              (id) => id != currentUserId,
              orElse: () => '',
            );

            final userData = _getCachedUserInfo(otherUserId);

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundImage:
                      userData['photoURL']?.isNotEmpty == true
                          ? NetworkImage(userData['photoURL'])
                          : null,
                  child: userData['photoURL']?.isEmpty == true
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(
                  userData['displayName'] ?? 'Unknown',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                subtitle: Text(
                  (convo['lastMessage'] as String?)?.isNotEmpty == true
                      ? convo['lastMessage']
                      : 'No messages yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTimestamp(convo['lastMessageTime'] as Timestamp?),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    if ((convo['unreadCount']?[currentUserId] ?? 0) > 0)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
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
                onTap: () => _openChatRoom(
                  context,
                  otherUserId,
                  userData['displayName'] ?? 'Unknown',
                  convo['id'],
                ),
              ),
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
              child:
                  _isLoadingUsers
                      ? const Center(child: CircularProgressIndicator())
                      : _availableUsers.isEmpty
                      ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No friends available'),
                      )
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _availableUsers.length,
                        itemBuilder: (ctx, index) {
                          final user = _availableUsers[index];
                          final alreadyChatted =
                              user['hasConversation'] == true;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage:
                                  user['photoURL'] != null &&
                                          user['photoURL'] != ''
                                      ? NetworkImage(user['photoURL'])
                                      : null,
                              child:
                                  (user['photoURL'] == null ||
                                          user['photoURL'] == '')
                                      ? const Icon(Icons.person)
                                      : null,
                            ),
                            title: Text(user['displayName'] ?? 'Unknown'),
                            subtitle: Text(user['email'] ?? ''),
                            trailing:
                                alreadyChatted
                                    ? const Icon(
                                      Icons.chat_bubble,
                                      color: Colors.grey,
                                      size: 16,
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
