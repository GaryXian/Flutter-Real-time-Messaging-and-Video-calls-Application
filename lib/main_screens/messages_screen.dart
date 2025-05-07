import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _generateConversationId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0 
        ? '${userId1}_$userId2' 
        : '${userId2}_$userId1';
  }

  void _openChatRoom(BuildContext context, String contactId, String contactName) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    final conversationId = _generateConversationId(currentUserId, contactId);
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ChatScreen(
          conversationId: conversationId,
          participants: [currentUserId, contactId],
        ),
      ),
    );
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
        automaticallyImplyLeading: true,
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
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final conversations = snapshot.data!.docs;

          if (conversations.isEmpty) {
            return const Center(child: Text('No conversations yet'));
          }

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (ctx, index) {
              final convo = conversations[index];
              final participants = List<String>.from(convo['participants']);
              final otherUserId = participants.firstWhere(
                (id) => id != currentUserId,
                orElse: () => '',
              );

              return FutureBuilder<DocumentSnapshot>(
                future: _firestore.collection('users').doc(otherUserId).get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                    );
                  }

                  final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                  
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: userData['photoURL'] != null 
                          ? NetworkImage(userData['photoURL'])
                          : null,
                      child: userData['photoURL'] == null 
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(userData['displayName'] ?? 'Unknown'),
                    subtitle: Text(
                      convo['lastMessage'] ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _formatTimestamp(convo['lastMessageTime'] as Timestamp?),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _openChatRoom(
                      context,
                      otherUserId,
                      userData['displayName'] ?? 'Unknown',
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
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.month}/${date.day}';
  }

  Future<void> _showNewChatDialog(BuildContext context) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    final users = await _firestore
        .collection('users')
        .where('uid', isNotEqualTo: currentUserId)
        .get();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start new chat'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: users.docs.length,
            itemBuilder: (ctx, index) {
              final user = users.docs[index].data();
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: user['photoURL'] != null 
                      ? NetworkImage(user['photoURL'])
                      : null,
                  child: user['photoURL'] == null 
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(user['displayName'] ?? 'Unknown'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openChatRoom(
                    context,
                    user['uid'],
                    user['displayName'] ?? 'Unknown',
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}