import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../main_screens/friends_screen.dart';
import '../main_screens/messages_screen.dart';
import '../main_screens/profile_screen.dart';
import '../widgets/call_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int navigateIndex = 0;
  final _firestore = FirebaseFirestore.instance;
  String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  StreamSubscription<DocumentSnapshot>? _callSubscription;

  List<Widget> screensList = const [
    MessagesScreen(),
    ContactsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _handlePermissionsAndNotifications(); // 👈 ask permissions and register token
    CallListenerService.startGlobalListening(context, _currentUserId!);
 // 👈 listen for incoming calls
  }

  Future<void> _handlePermissionsAndNotifications() async {
    // Ask notification permission (Android/iOS)
    await FirebaseMessaging.instance.requestPermission();

    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Optional: Ask for mic/camera if you're using calling
    await Permission.microphone.request();
    await Permission.camera.request();

    // Get and register FCM token
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (_currentUserId != null && fcmToken != null) {
      await FirebaseFirestore.instance.collection('users').doc(_currentUserId).update({
        'fcmToken': fcmToken,
      });
    }

    // Foreground message listener (optional)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("🔔 Foreground Notification: ${message.notification?.title}");
    });
  }


  @override
  void dispose() {
    CallListenerService.stopListening();
    _stopListeningForIncomingCalls();
    super.dispose();
  }

  void _stopListeningForIncomingCalls() {
    _callSubscription?.cancel();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: screensList[navigateIndex]),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: navigateIndex,
        onTap: (idx) {
          setState(() {
            navigateIndex = idx;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.contacts), label: 'Friends'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Me'),
        ],
        showUnselectedLabels: false,
        selectedItemColor: Colors.blue,
      ),
    );
  }
}
