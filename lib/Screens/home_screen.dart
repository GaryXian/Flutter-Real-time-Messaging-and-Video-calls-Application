import 'package:flutter/material.dart';
import 'package:realtime_message_and_video_call_application/Screens/contacts_screen.dart';
import 'package:realtime_message_and_video_call_application/Screens/profile_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Messages'),),
      
      body: ListView(
      ),
      
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (idx) {
          if (idx == 1) {
            Navigator.pushNamed(context, '/contacts');
          } else if (idx == 2) {
            Navigator.pushNamed(context, '/profile');
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.contacts), label: 'Contacts'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}