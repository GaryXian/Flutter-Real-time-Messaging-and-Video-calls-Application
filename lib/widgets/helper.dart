import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendSearchDelegate extends SearchDelegate<String> {
  final Future<void> Function(String query) onSearch;
  final Future<void> Function(String userId) onSendRequest;

  FriendSearchDelegate({required this.onSearch, required this.onSendRequest});

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    onSearch(query);
    return Center(child: Text('Searching for "$query"...'));
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('email', isGreaterThanOrEqualTo: query)
          .where('email', isLessThanOrEqualTo: '$query\uf8ff')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final results = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final email = data['email'] ?? '';
          final username = data['username'] ?? '';
          final phoneNumber = data['phoneNumber'] ?? '';

          // Search for matching email, username, or phone number
          return email.contains(query) ||
                 username.contains(query) ||
                 phoneNumber.contains(query);
        }).toList();

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
                  close(context, '');
                },
              ),
            );
          },
        );
      },
    );
  }
}

Widget buildUserAvatar(String? photoURL, {double radius = 24}) {
  if (photoURL != null && photoURL.isNotEmpty) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(photoURL),
      onBackgroundImageError: (_, __) {}, // Prevent crash
    );
  } else {
    return CircleAvatar(
      radius: radius,
      child: Icon(Icons.person, size: radius),
    );
  }
}

class UIHelper {
  static void showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        );
      },
    );
  }
}

