import 'package:flutter/material.dart';
import 'package:realtime_message_and_video_call_application/Screens/contacts_screen.dart';
import 'package:realtime_message_and_video_call_application/Screens/profile_screen.dart';
import 'Screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomePage(),
      routes: {
        '/contacts' : (ctx) => ContactsScreen(),
        '/profile': (ctx) => ProfileScreen(),
      }
    );
  }
}
