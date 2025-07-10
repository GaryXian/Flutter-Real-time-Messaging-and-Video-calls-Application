import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime_type/mime_type.dart';
import 'message_service.dart';


class MessageInput extends StatefulWidget {
  final String conversationId;
  final List<String> participants;
  final VoidCallback onSend;

  const MessageInput({
    super.key,
    required this.conversationId,
    required this.participants, 
    required this.onSend,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}
class ReplyData {
  final String messageId;
  final String content;
  final String senderId;

  ReplyData({required this.messageId, required this.content, required this.senderId});
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _messageService = MessageService();
  bool _isSending = false;

  Future<void> _sendTextMessage() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    
    if (widget.onSend != null) {
      widget.onSend();
    }

    setState(() => _isSending = true);
    await _messageService.sendMessage(
      conversationId: widget.conversationId,
      participants: widget.participants,
      content: content,
    );
    _controller.clear();
    setState(() => _isSending = false);
  }

  Future<void> _pickImage() async {
    try {
      final pickedImage = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (pickedImage == null) return;

      setState(() => _isSending = true);
      final url = await _messageService.uploadFile(
        conversationId: widget.conversationId,
        file: File(pickedImage.path),
      );
      final fileType = _messageService.getFileType(mime(pickedImage.path));

      await _messageService.sendMessage(
        conversationId: widget.conversationId,
        participants: widget.participants,
        fileUrl: url,
        fileType: fileType,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload image: ${e.toString()}')),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);

      setState(() => _isSending = true);
      final url = await _messageService.uploadFile(
        conversationId: widget.conversationId,
        file: file,
      );
      final fileType = _messageService.getFileType(mime(file.path));

      await _messageService.sendMessage(
        conversationId: widget.conversationId,
        participants: widget.participants,
        fileUrl: url,
        fileType: fileType,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload file: ${e.toString()}')),
      );
    } finally {
      setState(() => _isSending = false);
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
          IconButton(icon: const Icon(Icons.image), onPressed: _isSending ? null : _pickImage),
          IconButton(icon: const Icon(Icons.attach_file), onPressed: _isSending ? null : _pickFile),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: _isSending ? 'Sending...' : 'Type a message...',
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(25))),
              ),
              enabled: !_isSending,
              onSubmitted: (_) => _sendTextMessage(),
            ),
          ),
          IconButton(
            icon: _isSending ? const CircularProgressIndicator() : const Icon(Icons.send),
            onPressed: _isSending ? null : _sendTextMessage,
          ),
        ],
      ),
    );
  }
}
