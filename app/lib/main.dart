import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusPadApp());
}

class NexusPadApp extends StatelessWidget {
  const NexusPadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NexusPad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF2395f3),
        scaffoldBackgroundColor: const Color(0xFFeef4fd),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
