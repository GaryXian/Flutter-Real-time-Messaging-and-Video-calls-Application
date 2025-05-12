import 'package:flutter/material.dart';
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
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Dark theme'),
            subtitle: const Text('Enable or disable dark theme'),
            trailing: Switch(
              value: Provider.of<ThemeProvider>(context, listen: false).isDarkMode,
              onChanged: (isDarkMode) {
                Provider.of<ThemeProvider>(context, listen: false)
                    .toggleTheme();
              }
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
