import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/utils.dart';

class MessageInput extends StatefulWidget {
  final String receiverId;

  const MessageInput({super.key, required this.receiverId, required String conversationId});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  String _enteredMessage = '';

  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;

  Future<void> _sendMessage({String? fileUrl, String fileType = 'text'}) async {
    final user = _auth.currentUser;
    if (user == null || (_enteredMessage.trim().isEmpty && fileUrl == null)) return;

    final senderId = user.uid;
    final receiverId = widget.receiverId;
    final conversationId = getConversationId(senderId, receiverId);
    final timestamp = Timestamp.now();
    final content = _enteredMessage.trim();

    final messageRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc();

    await messageRef.set({
      'message_id': messageRef.id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'timestamp': timestamp,
      'is_read': false,
      'message_type': fileUrl != null ? fileType : 'text',
      'fileUrl': fileUrl ?? '',
    });

    await _firestore.collection('conversations').doc(conversationId).set({
      'conversation_id': conversationId,
      'participant_1': senderId,
      'participant_2': receiverId,
      'last_message_id': messageRef.id,
      'updated_at': timestamp,
    }, SetOptions(merge: true));

    _controller.clear();
    if (mounted) {
      setState(() => _enteredMessage = '');
    }
  }

  Future<void> _uploadAndSendFile({
    required File file,
    required String storagePath,
    required String fileType,
  }) async {
    final ref = _storage.ref().child(storagePath);
    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    await _sendMessage(fileUrl: url, fileType: fileType);
  }

  Future<void> _pickImage() async {
    final pickedImage = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedImage == null) return;

    final file = File(pickedImage.path);
    final filename = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _uploadAndSendFile(file: file, storagePath: 'chat_images/$filename', fileType: 'image');
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.single.path!);
    final filename = result.files.single.name;
    await _uploadAndSendFile(file: file, storagePath: 'chat_files/$filename', fileType: 'file');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          IconButton(onPressed: _pickImage, icon: const Icon(Icons.image)),
          IconButton(onPressed: _pickFile, icon: const Icon(Icons.attach_file)),
          Expanded(
            child: TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
              enableSuggestions: true,
              onChanged: (value) {
                setState(() => _enteredMessage = value);
              },
              onSubmitted: (_) => _sendMessage(),
              decoration: const InputDecoration(labelText: 'Send a message...'),
            ),
          ),
          IconButton(
            onPressed: _enteredMessage.trim().isEmpty ? null : () => _sendMessage(),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
