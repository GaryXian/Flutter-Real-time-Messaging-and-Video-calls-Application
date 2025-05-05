import 'package:flutter/material.dart';
import 'package:realtime_message_and_video_call_application/widgets/themes.dart';

class ThemeProvider with ChangeNotifier {
  ThemeData _themeData = lightMode;

  ThemeData get themeData => _themeData;

  set themeData(ThemeData themeData) {
    _themeData = themeData;
    notifyListeners();
  }

  bool isDarkMode = false;

  void toggleTheme() {
    if(_themeData == lightMode) {
      themeData = darkMode;
      isDarkMode = true;
    } else {
      themeData = lightMode;
      isDarkMode = false;
    }
  }
}