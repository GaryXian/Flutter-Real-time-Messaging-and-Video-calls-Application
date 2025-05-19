import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/call_screen.dart';

class CallListenerService {
  static StreamSubscription<DocumentSnapshot>? _subscription;
  static StreamSubscription<QuerySnapshot>? _globalSubscription;

static void startGlobalListening(BuildContext context, String currentUserId) {
  _globalSubscription?.cancel();

  _globalSubscription = FirebaseFirestore.instance
      .collection('calls')
      .where('receiverId', isEqualTo: currentUserId)
      .where('status', isEqualTo: 'ringing') // Only active calls
      .snapshots()
      .listen((querySnapshot) async {
    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      final callerId = data['callerId'];
      final conversationId = doc.id;
      final isVideoCall = data['isVideoCall'] ?? false;

      if (callerId == currentUserId) continue; // skip own call

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(callerId).get();
      final callerName = userDoc['displayName'] ?? 'Unknown';

      if (!context.mounted) return;

      // Show call dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: Text('Incoming ${isVideoCall ? "Video" : "Voice"} Call'),
            content: Text('$callerName is calling you'),
            actions: [
              TextButton(
                onPressed: () {
                  FirebaseFirestore.instance.collection('calls').doc(conversationId).update({
                    'status': 'declined',
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('Decline'),
              ),
              TextButton(
                onPressed: () {
                  FirebaseFirestore.instance.collection('calls').doc(conversationId).update({
                    'status': 'accepted',
                  });
                  Navigator.of(ctx).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallScreen(
                        conversationId: conversationId,
                        callerId: callerId,
                        receiverId: currentUserId,
                        isVideoCall: isVideoCall,
                      ),
                    ),
                  );
                },
                child: const Text('Accept'),
              ),
            ],
          );
        },
      );
    }
  });
}

static void stopGlobalListening() {
  _globalSubscription?.cancel();
}


  static void startListening(
    BuildContext context,
    String conversationId,
    String currentUserId,
  ) {
    final callDocRef = FirebaseFirestore.instance
        .collection('calls')
        .doc(conversationId);

    _subscription?.cancel(); // cancel previous listener if any
    _subscription = callDocRef.snapshots().listen((doc) async {
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;
      final callerId = data['callerId'];
      final isVideoCall = data['isVideoCall'] ?? false;
      final callStatus = data['status'] ?? 'ended'; // 👈 add this line

      if (callStatus != 'ringing') return; // 👈 skip if not a new call
      if (callerId == currentUserId) return;

      if (callerId == currentUserId) return;

      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(callerId)
              .get();
      final callerName = userDoc['displayName'] ?? 'Unknown';

      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: Text('Incoming ${isVideoCall ? "Video" : "Voice"} Call'),
            content: Text('$callerName is calling you'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                },
                child: const Text('Decline'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => CallScreen(
                            conversationId: conversationId,
                            callerId: callerId,
                            receiverId: currentUserId,
                            isVideoCall: isVideoCall,
                          ),
                    ),
                  );
                },
                child: const Text('Accept'),
              ),
            ],
          );
        },
      );
    });
  }

  static void stopListening() {
    _subscription?.cancel();
  }
}
