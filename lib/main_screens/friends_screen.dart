import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
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
      final friendsSnapshot =
          await _firestore
              .collection('users')
              .doc(currentUser.uid)
              .collection('friends')
              .get();

      final friends = friendsSnapshot.docs.map((doc) => doc.data()).toList();
      setState(() => _friendsList = friends);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load friends: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
      });
      return;
    }

    try {
      final snapshot =
          await _firestore
              .collection('users')
              .where(
                'email',
                isEqualTo: query,
              ) // Changed from range to exact match
              .get();

      final currentUser = _auth.currentUser;
      final results =
          snapshot.docs.where((doc) => doc.id != currentUser?.uid).map((doc) {
            final data = doc.data();
            return {
              ...data,
              'uid': doc.id, // Ensure uid is included
            };
          }).toList();

    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Search failed: ${e.toString()}')));
    } finally {
    }
  }

  Future<void> _sendFriendRequest(String userId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Check if already friends
      final friendDoc =
          await _firestore
              .collection('users')
              .doc(currentUser.uid)
              .collection('friends')
              .doc(userId)
              .get();

      if (friendDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This user is already your friend')),
        );
        return;
      }

      // Check if request already exists
      final requestDoc =
          await _firestore
              .collection('friend_requests')
              .doc('${currentUser.uid}_$userId')
              .get();

      if (requestDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request already sent')),
        );
        return;
      }

      // Create friend request
      await _firestore
          .collection('friend_requests')
          .doc('${currentUser.uid}_$userId')
          .set({
            'senderId': currentUser.uid,
            'receiverId': userId,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend request sent')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send request: ${e.toString()}')),
      );
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
            stream:
                _firestore
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

                      final userData =
                          userSnapshot.data!.data() as Map<String, dynamic>;
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
                        subtitle: Text(userData['email'] ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                              tooltip: 'Accept',
                              onPressed:
                                  () => _respondToRequest(
                                    senderId,
                                    request.id,
                                    accept: true,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              tooltip: 'Deny',
                              onPressed:
                                  () => _respondToRequest(
                                    senderId,
                                    request.id,
                                    accept: false,
                                  ),
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

  Future<void> _respondToRequest(
    String senderId,
    String requestId, {
    required bool accept,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final requestRef = _firestore
          .collection('friend_requests')
          .doc(requestId);

      if (accept) {
        // Add both users to each other's friend lists
        final senderDoc =
            await _firestore.collection('users').doc(senderId).get();
        final receiverDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();

        final senderData = senderDoc.data()!;
        final receiverData = receiverDoc.data()!;

        final batch = _firestore.batch();

        // Add sender to receiver's friends
        batch.set(
          _firestore
              .collection('users')
              .doc(currentUser.uid)
              .collection('friends')
              .doc(senderId),
          {
            'uid': senderId,
            'email': senderData['email'],
            'displayName': senderData['displayName'],
            'photoURL': senderData['photoURL'],
          },
        );

        // Add receiver to sender's friends
        batch.set(
          _firestore
              .collection('users')
              .doc(senderId)
              .collection('friends')
              .doc(currentUser.uid),
          {
            'uid': currentUser.uid,
            'email': receiverData['email'],
            'displayName': receiverData['displayName'],
            'photoURL': receiverData['photoURL'],
          },
        );

        // Update request status
        batch.update(requestRef, {'status': 'accepted'});

        await batch.commit();
        await _loadFriends();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request accepted')),
        );
      } else {
        // Deny: simply delete the request
        await requestRef.delete();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Friend request denied')));
      }

      Navigator.pop(context); // Close the modal after action
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: ${e.toString()}')));
    }
  }

  Future<void> _removeFriend(String friendId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      // Remove from both users' friend lists
      final batch = _firestore.batch();

      // Remove from current user's friends
      batch.delete(
        _firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('friends')
            .doc(friendId),
      );

      // Remove from friend's friends list
      batch.delete(
        _firestore
            .collection('users')
            .doc(friendId)
            .collection('friends')
            .doc(currentUser.uid),
      );

      await batch.commit();
      await _loadFriends(); // Refresh the list
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend removed')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove friend: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('Friends'),
        automaticallyImplyLeading: false,
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
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _friendsList.isEmpty
              ? const Center(
                child: Text('No friends yet. Search for users to add friends.'),
              )
              : ListView.builder(
                itemCount: _friendsList.length,
                itemBuilder: (context, index) {
                  final friend = _friendsList[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          friend['photoURL'] != null
                              ? NetworkImage(friend['photoURL'])
                              : null,
                      child:
                          friend['photoURL'] == null
                              ? const Icon(Icons.person)
                              : null,
                    ),
                    title: Text(friend['displayName'] ?? 'Unknown'),
                    subtitle: Text(friend['email'] ?? ''),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.red,
                      ),
                      onPressed: () => _removeFriend(friend['uid']),
                    ),
                  );
                },
              ),
    );
  }
}

class FriendSearchDelegate extends SearchDelegate {
  final Function(String) onSearch;
  final Function(String) onSendRequest;

  FriendSearchDelegate({required this.onSearch, required this.onSendRequest});

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
          onSearch(query);
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    onSearch(query);
    return const SizedBox(); // We'll show suggestions instead
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('users')
              .where('email', isGreaterThanOrEqualTo: query)
              .where('email', isLessThanOrEqualTo: '$query\uf8ff')
              .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final currentUser = FirebaseAuth.instance.currentUser;
        final results =
            snapshot.data!.docs
                .where((doc) => doc.id != currentUser?.uid)
                .map((doc) => doc.data() as Map<String, dynamic>)
                .toList();

        if (results.isEmpty) {
          return const Center(child: Text('No users found'));
        }

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final user = results[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    user['photoURL'] != null
                        ? NetworkImage(user['photoURL'])
                        : null,
                child:
                    user['photoURL'] == null ? const Icon(Icons.person) : null,
              ),
              title: Text(user['displayName'] ?? 'Unknown'),
              subtitle: Text(user['email'] ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.person_add),
                onPressed: () {
                  onSendRequest(user['uid']);
                  close(context, null);
                },
              ),
            );
          },
        );
      },
    );
  }
}
