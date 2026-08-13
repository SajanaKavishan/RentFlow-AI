import 'package:flutter/material.dart';

class MyViewingsScreen extends StatelessWidget {
  const MyViewingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Viewings')),
      body: const Center(child: Text('Your viewings will appear here.')),
    );
  }
}
