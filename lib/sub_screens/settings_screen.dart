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
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return ListTile(
                leading: const Icon(Icons.brightness_6),
                title: const Text('Dark theme'),
                subtitle: const Text('Enable or disable dark theme'),
                trailing: Switch(
                  activeColor: Colors.white,
                  value: themeProvider.isDarkMode,
                  onChanged: (isDarkMode) {
                    themeProvider.toggleTheme();
                  },
                ),
              );
            },
          ),
          const Divider(),
        ],
      ),
    );
  }
}
