import 'package:flutter/material.dart';
import '../screens/chat_screen.dart';
import '../screens/chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final List<Map<String, String>> dummyConversations = [
    {'name': 'Alice', 'lastMessage': 'Hey, how are you?'},
    {'name': 'Bob', 'lastMessage': 'Let\'s meet tomorrow'},
    {'name': 'Charlie', 'lastMessage': 'See you soon!'},
  ];

  void _openChatRoom(BuildContext context, String contactName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (ctx) => ChatScreen(
              receiverId: 'sampleReceiverId',
              conversationId: 'sampleConversationId',
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('Messages'),
        automaticallyImplyLeading: true,
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.add))],
      ),
      body: ListView.builder(
        itemCount: dummyConversations.length,
        itemBuilder: (ctx, index) {
          final convo = dummyConversations[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(convo['name'] ?? ''),
            subtitle: Text(convo['lastMessage'] ?? ''),
            onTap: () => _openChatRoom(context, convo['name'] ?? ''),
          );
        },
      ),
    );
  }
}
