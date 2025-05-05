import 'package:flutter/material.dart';

class InformationsScreen extends StatefulWidget {
  const InformationsScreen({super.key});

  @override
  State<InformationsScreen> createState() => _InformationsScreenState();
}

class _InformationsScreenState extends State<InformationsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: ListView(
            children: [
                ListTile(
                    title: Text('Profile image'),
                    //trailing: NetworkImage(url)
                    onTap: () {},
                ),
                Divider(),
                ListTile(
                    title: Text('Name'),
                    trailing: Text('Your name'),
                    onTap: () {},
                ),
                Divider(),
                ListTile(
                    title: Text('Mail'),
                    trailing: Text('abc@gmail.com'),
                    onTap: () {},
                ),
                Divider(),
                ListTile(
                    title: Text('My QR code'),
                    trailing: Icon(Icons.qr_code),
                    onTap: () {},
                ),
                Divider(),
            ],
        ),
    );
  }
}