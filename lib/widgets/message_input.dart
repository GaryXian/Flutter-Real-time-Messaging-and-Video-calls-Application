import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime_type/mime_type.dart';

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
  bool _isSending = false;

  Future<void> _sendMessage({String? fileUrl, String? fileType}) async {
    if (_currentUser == null || _isSending) return;

    final content = _controller.text.trim();
    if (content.isEmpty && fileUrl == null) return;

    setState(() => _isSending = true);

    try {
      final messageRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages')
          .doc();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Create the message
        transaction.set(messageRef, {
          'senderId': _currentUser.uid,
          'content': content,
          'fileUrl': fileUrl ?? '',
          'fileType': fileType ?? '',
          'timestamp': Timestamp.now(),
          'status': 'sent',
          'messageType': fileUrl != null ? fileType : 'text',
        });

        // Update conversation last message
        transaction.update(
          FirebaseFirestore.instance
              .collection('conversations')
              .doc(widget.conversationId),
          {
            'lastMessage': fileUrl != null 
                ? _getFileMessagePreview(fileType!) 
                : content,
            'lastMessageTime': Timestamp.now(),
            'lastMessageType': fileUrl != null ? fileType : 'text',
            'updatedAt': Timestamp.now(),
          },
        );
      });

      _controller.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: ${e.toString()}')),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  String _getFileMessagePreview(String fileType) {
    switch (fileType) {
      case 'image': return '📷 Photo';
      case 'video': return '🎥 Video';
      case 'audio': return '🔊 Audio';
      default: return '📄 File';
    }
  }

  Future<void> _uploadAndSendFile(File file) async {
    if (_currentUser == null) return;

    try {
      setState(() => _isSending = true);

      // Detect file type
      final mimeType = mime(file.path);
      final fileType = _getFileType(mimeType);

      // Generate storage path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = file.path.split('.').last;
      final filename = '$timestamp.$extension';
      final storagePath = 'chat_media/${widget.conversationId}/$fileType/$filename';

      // Upload file
      final ref = _storage.ref().child(storagePath);
      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await _sendMessage(fileUrl: url, fileType: fileType);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${e.toString()}')),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  String _getFileType(String? mimeType) {
    if (mimeType == null) return 'file';
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    return 'file';
  }

  Future<void> _pickImage() async {
    try {
      final pickedImage = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, // Reduce size for faster uploads
      );
      if (pickedImage == null) return;
      await _uploadAndSendFile(File(pickedImage.path));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: ${e.toString()}')),
      );
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      await _uploadAndSendFile(File(result.files.single.path!));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick file: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: _isSending ? null : _pickImage,
          ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _isSending ? null : _pickFile,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: _isSending ? 'Sending...' : 'Type a message...',
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                ),
              ),
              enabled: !_isSending,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: _isSending 
                ? const CircularProgressIndicator()
                : const Icon(Icons.send),
            onPressed: _isSending ? null : () => _sendMessage(),
          ),
        ],
      ),
    );
  }
}