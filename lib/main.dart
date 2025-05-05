import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:realtime_message_and_video_call_application/main_screens/friends_screen.dart';
import 'package:realtime_message_and_video_call_application/main_screens/messages_screen.dart';
import 'package:realtime_message_and_video_call_application/main_screens/profile_screen.dart';
import 'package:realtime_message_and_video_call_application/sub_screens/settings_screen.dart';
import 'package:realtime_message_and_video_call_application/authentication_screens/login_screen.dart';
import 'package:realtime_message_and_video_call_application/widgets/change_theme.dart';
import 'home/home.dart';


void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp()
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const LoginScreen(),
      theme: Provider.of<ThemeProvider>(context).themeData,
      routes: {
        '/login' : (ctx) => LoginScreen(),
        '/home' : (ctx) => HomePage(),
        '/message' : (ctx) => MessagesScreen(),
        '/contacts' : (ctx) => ContactsScreen(),
        '/profile' : (ctx) => ProfileScreen(),
        '/settings' : (ctx) => SettingsScreen(), 
      }
    );
  }
}
