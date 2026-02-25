import 'package:flutter/material.dart';
import 'package:gp_hudai/core/constants/colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color.fromARGB(156, 201, 203, 230)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
     
    );
  }
}
