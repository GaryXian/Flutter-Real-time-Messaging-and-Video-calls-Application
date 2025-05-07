import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class MessageInput extends StatefulWidget {
  final String conversationId;
  final List<String> participants;

  const MessageInput({
    super.key,
    required this.conversationId,
    required this.participants,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _storage = FirebaseStorage.instance;

  Future<void> _sendMessage({String? fileUrl, String? fileType}) async {
    if (_currentUser == null) return;

    final content = _controller.text.trim();
    if (content.isEmpty && fileUrl == null) return;

    final messageRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .doc();

    await messageRef.set({
      'senderId': _currentUser.uid,
      'content': content,
      'fileUrl': fileUrl ?? '',
      'fileType': fileType ?? '',
      'timestamp': Timestamp.now(),
      'status': 'sent',
      'messageType': fileUrl != null ? fileType : 'text',
    });

    // Update conversation last message
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .update({
      'lastMessage': fileUrl != null ? 'Sent an attachment' : content,
      'lastMessageTime': Timestamp.now(),
      'lastMessageType': fileUrl != null ? fileType : 'text',
    });

    _controller.clear();
  }

  // ... (keep existing _pickImage, _pickFile, _uploadAndSendFile methods)
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
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: _pickImage,
          ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _pickFile,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendMessage(),
          ),
        ],
      ),
    );
  }
}