import 'package:flutter/material.dart';
import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/core/constants/colors.dart';


class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الكاميرا'),
        actions: [
        IconButton(
  icon: const Icon(Icons.settings, color: Color.fromARGB(156, 201, 203, 230)),
  onPressed: () {
    Navigator.pushNamed(context, AppRoutes.settings);
  },
),

        ],
      ),
     
    );
  }
}
