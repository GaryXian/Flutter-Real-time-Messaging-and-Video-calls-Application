// screens/test_call_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/call_screen.dart';

class TestCallScreen extends StatefulWidget {
  const TestCallScreen({super.key});

  @override
  State<TestCallScreen> createState() => _TestCallScreenState();
}

class _TestCallScreenState extends State<TestCallScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  List<Map<String, dynamic>> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    setState(() => _isLoading = true);
    try {
      final friendsSnapshot = await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('friends')
          .get();

      final friendsData = await Future.wait(friendsSnapshot.docs.map((doc) async {
        final userDoc = await _firestore.collection('users').doc(doc.id).get();
        final data = userDoc.data();
        if (data != null) {
          return {
            'uid': userDoc.id,
            'displayName': data['displayName'] ?? 'Unknown',
            'email': data['email'] ?? '',
            'photoURL': data['photoURL'] ?? '',
          };
        } else {
          return {};
        }
      }));

      setState(() {
        _friends = friendsData.where((u) => u.isNotEmpty).toList().cast<Map<String, dynamic>>();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _generateConversationId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }

  void _startCall(Map<String, dynamic> friend, bool isVideoCall) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    final conversationId = _generateConversationId(currentUserId, friend['uid']);

    // Ensure conversation exists (optional for call)
    final conversationDoc = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .get();

    if (!conversationDoc.exists) {
      await _firestore.collection('conversations').doc(conversationId).set({
        'conversationId': conversationId,
        'participants': [currentUserId, friend['uid']],
        'participantNames': {
          currentUserId: _auth.currentUser?.displayName ?? 'You',
          friend['uid']: friend['displayName'] ?? 'Unknown',
        },
        'lastMessage': 'Conversation started (for call)',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'unreadCount': {
          currentUserId: 0,
          friend['uid']: 1,
        },
      });
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => CallScreen(
          conversationId: conversationId,
          callerId: currentUserId,
          receiverId: friend['uid'],
          isVideoCall: isVideoCall,
          //isVideo: isVideoCall,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Call')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? const Center(child: Text('No friends available'))
              : ListView.builder(
                  itemCount: _friends.length,
                  itemBuilder: (ctx, index) {
                    final user = _friends[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user['photoURL'] != null
                            ? NetworkImage(user['photoURL'])
                            : null,
                        child: user['photoURL'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(user['displayName']),
                      subtitle: Text(user['email']),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.call),
                            onPressed: () => _startCall(user, false),
                          ),
                          IconButton(
                            icon: const Icon(Icons.videocam),
                            onPressed: () => _startCall(user, true),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
