import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/helper.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _friendsList = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _isLoading = true);
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final friendsSnapshot = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('friends')
          .get();

      final friends = friendsSnapshot.docs.map((doc) => doc.data()).toList();
      setState(() => _friendsList = friends);
    } catch (e) {
      _showSnack('Failed to load friends: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) return;
    try {
      await _firestore
          .collection('users')
          .where('email', isEqualTo: query)
          .get();
    } catch (e) {
      _showSnack('Search failed: ${e.toString()}');
    }
  }

  Future<void> _sendFriendRequest(String userId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || userId == currentUser.uid) {
      _showSnack('Invalid user');
      return;
    }

    try {
      final isFriend = await _firestore
          .collection('users')
          .doc(userId)
          .collection('friends')
          .doc(currentUser.uid)
          .get();

      final requestSent = await _firestore
          .collection('friend_requests')
          .doc('${currentUser.uid}_$userId')
          .get();
      final requestReceived = await _firestore
          .collection('friend_requests')
          .doc('${userId}_${currentUser.uid}')
          .get();

      if (isFriend.exists || requestSent.exists || requestReceived.exists) {
        _showSnack('Already friends or request exists');
        return;
      }

      await _firestore.collection('friend_requests').doc('${currentUser.uid}_$userId').set({
        'senderId': currentUser.uid,
        'receiverId': userId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showSnack('Friend request sent');
    } catch (e) {
      _showSnack('Failed: ${e.toString()}');
    }
  }

  Future<void> _removeFriend(String friendId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final batch = _firestore.batch();

      batch.delete(_firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('friends')
          .doc(friendId));

      batch.delete(_firestore
          .collection('users')
          .doc(friendId)
          .collection('friends')
          .doc(currentUser.uid));

      await batch.commit();
      await _loadFriends();
      _showSnack('Friend removed');
    } catch (e) {
      _showSnack('Failed to remove friend: ${e.toString()}');
    }
  }

  Future<void> _showFriendRequests() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('friend_requests')
                .where('receiverId', isEqualTo: currentUser.uid)
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No friend requests.'));
              }

              final requests = snapshot.data!.docs;
              return ListView.builder(
                shrinkWrap: true,
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final request = requests[index];
                  final senderId = request['senderId'];

                  return FutureBuilder<DocumentSnapshot>(
                    future: _firestore.collection('users').doc(senderId).get(),
                    builder: (context, userSnapshot) {
                      if (!userSnapshot.hasData) {
                        return const ListTile(title: Text('Loading...'));
                      }

                      final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                      return ListTile(
                        leading: buildUserAvatar(userData['photoURL']),
                        title: Text(userData['displayName'] ?? 'Unknown'),
                        subtitle: Text(userData['email'] ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              tooltip: 'Accept',
                              onPressed: () => _respondToRequest(senderId, request.id, accept: true),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              tooltip: 'Deny',
                              onPressed: () => _respondToRequest(senderId, request.id, accept: false),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _respondToRequest(String senderId, String requestId, {required bool accept}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final requestRef = _firestore.collection('friend_requests').doc(requestId);

      if (accept) {
        final senderDoc = await _firestore.collection('users').doc(senderId).get();
        final receiverDoc = await _firestore.collection('users').doc(currentUser.uid).get();

        final senderData = senderDoc.data()!;
        final receiverData = receiverDoc.data()!;

        final batch = _firestore.batch();

        batch.set(
          _firestore.collection('users').doc(currentUser.uid).collection('friends').doc(senderId),
          {
            'uid': senderId,
            'email': senderData['email'],
            'displayName': senderData['displayName'],
            'photoURL': senderData['photoURL'],
          },
        );

        batch.set(
          _firestore.collection('users').doc(senderId).collection('friends').doc(currentUser.uid),
          {
            'uid': currentUser.uid,
            'email': receiverData['email'],
            'displayName': receiverData['displayName'],
            'photoURL': receiverData['photoURL'],
          },
        );

        batch.update(requestRef, {'status': 'accepted'});
        await batch.commit();

        await _loadFriends();
        _showSnack('Friend request accepted');
      } else {
        await requestRef.delete();
        _showSnack('Friend request denied');
      }

      Navigator.pop(context);
    } catch (e) {
      _showSnack('Failed: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Friend Requests',
            onPressed: _showFriendRequests,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search Users',
            onPressed: () {
              showSearch(
                context: context,
                delegate: FriendSearchDelegate(
                  onSearch: _searchUsers,
                  onSendRequest: _sendFriendRequest,
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _friendsList.isEmpty
              ? const Center(child: Text('No friends yet. Search to add friends.'))
              : ListView.builder(
                  itemCount: _friendsList.length,
                  itemBuilder: (context, index) {
                    final friend = _friendsList[index];
                    return ListTile(
                      leading: buildUserAvatar(friend['photoURL']),
                      title: Text(friend['displayName'] ?? 'Unknown'),
                      subtitle: Text(friend['email'] ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () => _removeFriend(friend['uid']),
                      ),
                    );
                  },
                ),
    );
  }
}
