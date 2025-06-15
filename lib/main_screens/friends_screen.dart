import 'dart:async';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/chat_screen.dart';
import '../widgets/helper.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _friendsSubscription;

  List<Map<String, dynamic>> _friendsList = [];
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoading = false;

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

    // Populate _friendsList with friends data
    _friendsList = friendsSnapshot.docs.map((doc) => {
      'uid': doc.id,
      ...doc.data(),
    }).toList();

    // Initialize _availableUsers with all friends
    _availableUsers = []; 

    _availableUsers = List.from(_friendsList);

  } catch (e) {
    _showSnack('Failed to load friends: ${e.toString()}');
  } finally {
    setState(() => _isLoading = false);
  }
}

@override
void dispose() {
  _friendsSubscription?.cancel();
  super.dispose();
}

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _searchUsers(String query) async {
  if (query.isEmpty) {
    setState(() {
      _availableUsers = []; // Reset search results
    });
    return;
  }

  try {
    final usersSnapshot = await _firestore
        .collection('users')
        .where('displayName', isGreaterThanOrEqualTo: query)
        .where('displayName', isLessThanOrEqualTo: '$query\uf8ff')
        .get();

    setState(() {
      _availableUsers = usersSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'uid': doc.id,
          'displayName': data['displayName'] ?? 'Unknown',
          'email': data['email'] ?? '',
          'photoURL': data['photoURL'] ?? '',
        };
      }).toList();
    });
  } catch (e) {
    _showSnack('Search failed: ${e.toString()}');
  }
}

  String _generateRequestId(String senderId, String receiverId) {
    return '${senderId}_$receiverId';
  }

  Future<void> _sendFriendRequest(String userId, String displayName) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final displayName = userDoc.data()?['displayName'] ?? 'Unknown';
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _showSnack('You must be logged in');
      return;
    }

    if (userId == currentUser.uid) {
      _showSnack('You cannot send a request to yourself');
      return;
    }
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Send Friend Request'),
            content: Text('Do you want to send a friend request to $displayName?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Send'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

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
        _showSnack('You are already friends with $displayName');
        return;
      }

      // Generate consistent request ID
      final requestId = _generateRequestId(currentUser.uid, userId);
      final requestRef = _firestore
          .collection('friend_requests')
          .doc(requestId);

      // Check for existing request
      final existingRequest = await requestRef.get();
      if (existingRequest.exists) {
        final status = existingRequest.data()?['status'] ?? 'pending';
        _showSnack(
          status == 'pending'
              ? 'Friend request already sent to $displayName'
              : 'Previous request was ${status}',
        );
        return;
      }

      // Create the request
      await _firestore.runTransaction((transaction) async {
        // Verify again in transaction
        final freshCheck = await transaction.get(requestRef);
        if (freshCheck.exists) {
          throw Exception('Request already exists');
        }

        transaction.set(requestRef, {
          'senderId': currentUser.uid,
          'receiverId': userId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Update counters (optional)
        transaction.update(
          _firestore.collection('users').doc(currentUser.uid),
          {'pendingSentRequests': FieldValue.increment(1)},
        );
        transaction.update(_firestore.collection('users').doc(userId), {
          'pendingReceivedRequests': FieldValue.increment(1),
        });
      });

      _showSnack('Friend request sent to $displayName');
    } on FirebaseException catch (e) {
      _showSnack('Failed to send request: ${e.message}');
    } catch (e) {
      _showSnack('An unexpected error occurred');
      debugPrint('Error sending friend request: $e');
    }
  }
  
  Future<void> _removeFriend(String ContactId, String friendName) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Remove Friend'),
            content: Text(
              'Are you sure you want to remove $friendName from your friends?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    // If user confirmed removal
    if (confirm == true) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );

        final batch = _firestore.batch();

        // Remove from current user's friends
        batch.delete(
          _firestore
              .collection('users')
              .doc(currentUser.uid)
              .collection('friends')
              .doc(ContactId),
        );

        // Remove from friend's friends list
        batch.delete(
          _firestore
              .collection('users')
              .doc(ContactId)
              .collection('friends')
              .doc(currentUser.uid),
        );

        await batch.commit();

        // Close loading dialog
        if (mounted) Navigator.pop(context);

        // Refresh friends list
        await _loadFriends();

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$friendName removed from friends')),
          );
        }
      } catch (e) {
        // Close loading dialog if still mounted
        if (mounted) Navigator.pop(context);

        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove friend: ${e.toString()}')),
          );
        }
      }
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
                        leading: buildUserAvatar(userData['photoURL']),
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

    final actionText = accept ? 'accept' : 'deny';
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('${accept ? "Accept" : "Deny"} Friend Request'),
            content: Text(
              'Are you sure you want to $actionText this friend request?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  actionText[0].toUpperCase() + actionText.substring(1),
                  style: TextStyle(color: accept ? Colors.green : Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      final requestRef = _firestore
          .collection('friend_requests')
          .doc(requestId);

      if (accept) {
        final senderDoc =
            await _firestore.collection('users').doc(senderId).get();
        final receiverDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();

        final senderData = senderDoc.data()!;
        final receiverData = receiverDoc.data()!;

        final batch = _firestore.batch();

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

String _generateConversationId(String ContactId) {
  final currentUserId = _auth.currentUser!.uid;
  return currentUserId.compareTo(ContactId) < 0 
      ? '${currentUserId}_$ContactId' 
      : '${ContactId}_$currentUserId';
}

Future<void> _blockFriend(String ContactId) async {
  final currentUserId = _auth.currentUser!.uid;
  
  try {
    await _firestore.collection('users').doc(currentUserId).update({
      'blockedUsers': FieldValue.arrayUnion([ContactId]),
    });
    _showSnack('You have blocked this friend.');
  } catch (e) {
    _showSnack('Failed to block friend: ${e.toString()}');
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
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
                  onSendRequest: (userId) => _sendFriendRequest(userId, 'Unknown'),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _friendsList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.group_off, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No friends yet',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('Search and send friend requests to start connecting.'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _availableUsers.length, // Use available users
                  itemBuilder: (context, index) {
                    final friend = _availableUsers[index];  // Use available users

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Slidable(
                        key: Key(friend['uid']),
                        endActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          extentRatio: 0.25,
                          children: [
                            SlidableAction(
                              onPressed: (context) => _removeFriend(friend['uid'], friend['displayName']),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              icon: Icons.delete,
                              label: 'Remove',
                            ),
                          ],
                        ),
                        child: GestureDetector(
                          onTap: () {
                            // Navigate to chat room
                            Navigator.push(
                            context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(
                                  conversationId: _generateConversationId(friend['uid']),
                                  participants: [_auth.currentUser!.uid, friend['uid']],
                                ),
                              ),
                            );
                          },
                          child: Material(
                            elevation: 2,
                            borderRadius: BorderRadius.circular(16),
                            color: Theme.of(context).cardColor,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              leading: buildUserAvatar(friend['photoURL']),
                              title: Text(
                                friend['displayName'] ?? 'Unknown',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(friend['email'] ?? ''),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    _removeFriend(friend['uid'], friend['displayName']);
                                  } else if (value == 'block') {
                                    _blockFriend(friend['uid']);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete Friend'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'block',
                                    child: Text('Block Friend'),
                                  ),
                                ],
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
