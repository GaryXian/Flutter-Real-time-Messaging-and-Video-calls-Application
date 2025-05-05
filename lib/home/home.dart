import 'package:flutter/material.dart';
import 'package:realtime_message_and_video_call_application/main_screens/friends_screen.dart';
import 'package:realtime_message_and_video_call_application/main_screens/messages_screen.dart';
import 'package:realtime_message_and_video_call_application/main_screens/profile_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int navigateIndex = 0;

  List<Widget> screensList = const [
    MessagesScreen(),
    ContactsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: screensList[navigateIndex],),
      
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: navigateIndex,
        onTap: (idx) {
          setState(() {
            navigateIndex = idx;
          });
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.contacts), label: 'Friends'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Me'),
        ],
        showUnselectedLabels: false,
      ),
    );
  }
}