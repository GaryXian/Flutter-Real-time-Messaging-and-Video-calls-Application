import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/call_screen.dart';

class CallListenerService {
  static StreamSubscription<DocumentSnapshot>? _subscription;
  static StreamSubscription<QuerySnapshot>? _globalSubscription;
  static final Set<String> _handledCallIds = {}; // ✅ Track handled calls

  static void startGlobalListening(BuildContext context, String currentUserId) {
    _globalSubscription?.cancel();

    _globalSubscription = FirebaseFirestore.instance
        .collection('calls')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((querySnapshot) async {
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final callerId = data['callerId'];
        final conversationId = doc.id;
        final isVideoCall = data['isVideoCall'] ?? false;

        if (callerId == currentUserId) continue;
        if (_handledCallIds.contains(conversationId)) continue; // ✅ Prevent duplicate

        await _showIncomingCallDialog(
          context,
          conversationId,
          callerId,
          currentUserId,
          isVideoCall,
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
    final callDocRef =
        FirebaseFirestore.instance.collection('calls').doc(conversationId);

    _subscription?.cancel();
    _subscription = callDocRef.snapshots().listen((doc) async {
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      final callerId = data['callerId'];
      final isVideoCall = data['isVideoCall'] ?? false;
      final callStatus = data['status'] ?? 'ended';

      if (callStatus != 'ringing') return;
      if (callerId == currentUserId) return;
      if (_handledCallIds.contains(conversationId)) return; // ✅ Prevent duplicate

      await _showIncomingCallDialog(
        context,
        conversationId,
        callerId,
        currentUserId,
        isVideoCall,
      );
    });
  }

  static void stopListening() {
    _subscription?.cancel();
  }

  static Future<void> _showIncomingCallDialog(
    BuildContext context,
    String conversationId,
    String callerId,
    String currentUserId,
    bool isVideoCall,
  ) async {
    _handledCallIds.add(conversationId); // ✅ Mark this call as handled

    final userDoc = await FirebaseFirestore.instance
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
                FirebaseFirestore.instance
                    .collection('calls')
                    .doc(conversationId)
                    .update({'status': 'declined'});
                Navigator.of(ctx).pop();
              },
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: () {
                FirebaseFirestore.instance
                    .collection('calls')
                    .doc(conversationId)
                    .update({'status': 'accepted'});
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
}
