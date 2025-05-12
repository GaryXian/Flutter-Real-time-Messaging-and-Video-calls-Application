import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'home/home.dart';
import 'main_screens/friends_screen.dart';
import 'main_screens/messages_screen.dart';
import 'main_screens/profile_screen.dart';
import 'authentication_screens/login_screen.dart';
import 'sub_screens/settings_screen.dart';
import 'sub_screens/test_call.dart';
import 'sub_screens/test_message.dart';
import 'widgets/change_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Realtime Message & Video Call App',
      theme: Provider.of<ThemeProvider>(context).themeData,
      routes: {
        '/login': (ctx) => const LoginScreen(),
        '/home': (ctx) => const HomePage(),
        '/message': (ctx) => const MessagesScreen(),
        '/contacts': (ctx) => const ContactsScreen(),
        '/profile': (ctx) => const ProfileScreen(),
        '/settings': (ctx) => const SettingsScreen(),
        '/test-message': (ctx) => const TestMessageScreen(),
        '/test-call': (ctx) => const TestCallScreen(),
      },
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const HomePage();
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }
}
