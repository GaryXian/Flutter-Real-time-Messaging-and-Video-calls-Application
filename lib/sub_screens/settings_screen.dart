import 'package:flutter/material.dart';
import '../main_screens/profile_screen.dart';
import '../widgets/change_theme.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Dark theme'),
            subtitle: const Text('Enable or disable dark theme'),
            trailing: Switch(
              value: themeProvider.isDarkMode,
              onChanged: (isDarkMode) {
                themeProvider.toggleTheme();
              },
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
