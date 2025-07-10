// lib/services/message_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/semantics.dart';
import 'package:mime_type/mime_type.dart';

class MessageService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  String getFileType(String? mimeType) {
    if (mimeType == null) return 'file';
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    return 'file';
  }

  String getFileMessagePreview(String fileType) {
    switch (fileType) {
      case 'image': return '📷 Photo';
      case 'video': return '🎥 Video';
      case 'audio': return '🔊 Audio';
      default: return '📄 File';
    }
  }

  Future<String?> uploadFile({
    required String conversationId,
    required File file,
  }) async {
    final mimeType = mime(file.path);
    final fileType = getFileType(mimeType);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = file.path.split('.').last;
    final filename = '$timestamp.$extension';
    final storagePath = 'chat_media/$conversationId/$fileType/$filename';

    final ref = _storage.ref().child(storagePath);
    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    return url;
  }

  Future<void> sendMessage({
    required String conversationId,
    required List<String> participants,
    String content = '',
    String? fileUrl,
    String? fileType,
  }) async {
    final user = currentUser;
    if (user == null) return;
    if (content.isEmpty && fileUrl == null) return;

    final messageRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc();

    await _firestore.runTransaction((transaction) async {
      transaction.set(messageRef, {
        'senderId': user.uid,
        'content': content,
        'fileUrl': fileUrl ?? '',
        'fileType': fileType ?? '',
        'timestamp': Timestamp.now(),
        'status': 'sent',
        'messageType': fileUrl != null ? fileType : 'text',
      });

      transaction.update(
        _firestore.collection('conversations').doc(conversationId),
        {
          'lastMessage': fileUrl != null
              ? getFileMessagePreview(fileType!)
              : content,
          'lastMessageTime': Timestamp.now(),
          'lastMessageType': fileUrl != null ? fileType : 'text',
          'updatedAt': Timestamp.now(),
        },
      );
    });
  }
}
