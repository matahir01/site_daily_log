import 'package:flutter/material.dart';
import 'screens/project_list_screen.dart';

void main() {
  runApp(const SiteDailyLogApp());
}

class SiteDailyLogApp extends StatelessWidget {
  const SiteDailyLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Site Daily Log',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.orange,
        useMaterial3: true,
      ),
      home: const ProjectListScreen(),
    );
  }
}
