// lib/models/MessageModel.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  String messageid;
  String sender;
  DateTime createdon;
  String text;
  bool seen;

  MessageModel({
    required this.messageid,
    required this.sender,
    required this.createdon,
    required this.text,
    required this.seen,
  });

  MessageModel.fromMap(Map<String, dynamic> map)
      : messageid = map['messageid'] ?? '',
        sender = map['sender'] ?? '',
        createdon = (map['createdon'] as Timestamp).toDate(),
        text = map['text'] ?? '',
        seen = map['seen'] ?? false;

  Map<String, dynamic> toMap() {
    return {
      'messageid': messageid,
      'sender': sender,
      'createdon': createdon,
      'text': text,
      'seen': seen,
    };
  }
}
